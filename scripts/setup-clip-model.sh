#!/usr/bin/env bash
# Export OpenAI CLIP ViT-B/32 vision encoder to ONNX for local image moderation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_DIR="$ROOT/backend/models/clip"
EMBEDDINGS="$ROOT/backend/src/main/resources/models/clip-text-embeddings.json"

echo "==> Installing Python deps (torch, transformers, onnx)..."
python3 -m pip install --quiet torch transformers pillow numpy onnx

echo "==> Generating label text embeddings..."
export CLIP_EMBEDDINGS_PATH="$EMBEDDINGS"
python3 << PY
import json, os, torch
from transformers import CLIPModel, CLIPProcessor

model_id = "openai/clip-vit-base-patch32"
model = CLIPModel.from_pretrained(model_id)
processor = CLIPProcessor.from_pretrained(model_id)

labels = [
    "nudity or sexual content", "pornographic content",
    "violence or gore", "blood or graphic injury",
    "firearms or weapons", "knife or bladed weapon",
    "drugs or drug paraphernalia", "hate symbols or extremist imagery",
    "self harm or suicide", "graphic medical imagery",
    "gambling", "safe everyday content",
]
categories = {
    "nudity or sexual content": "ADULT", "pornographic content": "ADULT",
    "violence or gore": "VIOLENCE", "blood or graphic injury": "VIOLENCE",
    "firearms or weapons": "WEAPONS", "knife or bladed weapon": "WEAPONS",
    "drugs or drug paraphernalia": "DRUGS",
    "hate symbols or extremist imagery": "HATE_SYMBOLS",
    "self harm or suicide": "SELF_HARM", "graphic medical imagery": "GRAPHIC_MEDICAL",
    "gambling": "GAMBLING",
    "safe everyday content": None,
}
inputs = processor(text=labels, return_tensors="pt", padding=True)
with torch.no_grad():
    feats = model.get_text_features(**inputs)
    feats = feats / feats.norm(dim=-1, keepdim=True)
out = {"model": model_id, "dimension": 512, "labels": []}
for i, label in enumerate(labels):
    out["labels"].append({
        "text": label,
        "category": categories[label],
        "embedding": feats[i].tolist(),
    })
import os
path = os.environ["CLIP_EMBEDDINGS_PATH"]
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(out, f)
print("Wrote embeddings:", path)
PY

echo "==> Exporting vision encoder ONNX (~350MB, one-time)..."
mkdir -p "$MODEL_DIR"
python3 << PY
import os, torch
from transformers import CLIPModel

out = "$MODEL_DIR/vision_model.onnx"
model = CLIPModel.from_pretrained("openai/clip-vit-base-patch32")
model.eval()

class VisionEncoder(torch.nn.Module):
    def __init__(self, clip):
        super().__init__()
        self.vision = clip.vision_model
        self.visual_projection = clip.visual_projection
    def forward(self, pixel_values):
        return self.visual_projection(self.vision(pixel_values).pooler_output)

enc = VisionEncoder(model)
enc.eval()
dummy = torch.randn(1, 3, 224, 224)
torch.onnx.export(enc, dummy, out,
    input_names=["pixel_values"], output_names=["image_embeds"],
    dynamic_axes={"pixel_values": {0: "batch"}, "image_embeds": {0: "batch"}},
    opset_version=14)
print("Wrote", out, os.path.getsize(out), "bytes")
PY

echo "==> Done. Restart the backend to load CLIP ONNX."
