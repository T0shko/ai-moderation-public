#!/usr/bin/env bash
# Verify Hugging Face token + Inference API from repo-root .env
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi
if [[ -z "${HUGGINGFACE_API_TOKEN:-}" ]]; then
  echo "❌ HUGGINGFACE_API_TOKEN is not set in $ROOT/.env"
  exit 1
fi
echo "==> Whoami (token valid?)..."
curl -sS -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" \
  https://huggingface.co/api/whoami-v2 | python3 -c "import sys,json; d=json.load(sys.stdin); print('✅ User:', d.get('name'))"

echo "==> Inference probe (Falconsai/nsfw_image_detection)..."
python3 << 'PY'
import os, json, urllib.request
from pathlib import Path
token = os.environ["HUGGINGFACE_API_TOKEN"]
try:
    from PIL import Image
    import io
    buf = io.BytesIO()
    Image.new("RGB", (224, 224), (100, 120, 180)).save(buf, format="JPEG")
    jpg = buf.getvalue()
except ImportError:
    jpg = Path("/tmp/test224.jpg").read_bytes() if Path("/tmp/test224.jpg").exists() else None
    if jpg is None:
        raise SystemExit("Install pillow or create /tmp/test224.jpg")
url = "https://router.huggingface.co/hf-inference/models/Falconsai/nsfw_image_detection"
req = urllib.request.Request(url, data=jpg, method="POST", headers={
    "Authorization": f"Bearer {token}",
    "Content-Type": "image/jpeg",
    "x-wait-for-model": "true",
})
with urllib.request.urlopen(req, timeout=90) as resp:
    body = json.loads(resp.read().decode())
    print("✅ Inference OK:", body[:2] if isinstance(body, list) else body)
PY
echo "Done. Restart backend after changing .env."
