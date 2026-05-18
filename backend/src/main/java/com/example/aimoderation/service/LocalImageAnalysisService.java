package com.example.aimoderation.service;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;
import com.example.aimoderation.model.ImageContentCategory;
import com.example.aimoderation.model.ImageModerationStatus;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import javax.imageio.ImageIO;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.FloatBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.EnumMap;
import java.util.Map;

/**
 * Self-hosted CLIP ViT-B/32 zero-shot image moderation (same approach as HuggingFace CLIP API).
 * Uses ONNX Runtime locally — no pixel heuristics, no external API required for this layer.
 */
@Service
public class LocalImageAnalysisService {

    private static final Logger logger = LoggerFactory.getLogger(LocalImageAnalysisService.class);

    private static final int INPUT_SIZE = 224;
    private static final float[] MEAN = {0.48145466f, 0.4578275f, 0.40821073f};
    private static final float[] STD = {0.26862954f, 0.26130258f, 0.27577711f};

    private static final double FLAG_THRESHOLD = 0.15;
    private static final double FLAG_THRESHOLD_WEAPONS = 0.11;
    private static final double REJECT_THRESHOLD = 0.35;
    @Value("${moderation.image.clip.embeddings-path:models/clip-text-embeddings.json}")
    private String embeddingsClasspath;

    @Value("${moderation.image.clip.vision-model-path:models/clip/vision_model.onnx}")
    private String visionModelPath;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private OrtEnvironment ortEnv;
    private OrtSession ortSession;
    private List<LabelEmbedding> labelEmbeddings = List.of();
    private LabelEmbedding safeAnchor;
    private boolean modelReady;

    @PostConstruct
    public void init() {
        try {
            labelEmbeddings = loadLabelEmbeddings();
            safeAnchor = labelEmbeddings.stream()
                    .filter(l -> l.category() == null)
                    .findFirst()
                    .orElse(null);

            Path modelFile = resolveVisionModelPath();
            if (!Files.isRegularFile(modelFile)) {
                logger.error(
                        "CLIP vision ONNX model not found (tried paths for {}). Run: ./scripts/setup-clip-model.sh",
                        visionModelPath);
                modelReady = false;
                return;
            }

            ortEnv = OrtEnvironment.getEnvironment();
            ortSession = ortEnv.createSession(modelFile.toString(), new OrtSession.SessionOptions());
            modelReady = true;
            logger.info("Local CLIP ONNX ready: {} labels, model={}", labelEmbeddings.size(), modelFile);
        } catch (Exception e) {
            logger.error("Failed to initialize local CLIP ONNX engine: {}", e.getMessage(), e);
            modelReady = false;
        }
    }

    @PreDestroy
    public void shutdown() {
        try {
            if (ortSession != null) ortSession.close();
        } catch (OrtException e) {
            logger.warn("Error closing ONNX session: {}", e.getMessage());
        }
    }

    public AnalysisResult analyze(byte[] imageData) {
        if (!modelReady) {
            return new AnalysisResult(
                    ImageModerationStatus.ERROR,
                    0.0,
                    Collections.emptyList(),
                    "Local CLIP model not installed. Run ./scripts/setup-clip-model.sh from the project root.");
        }

        try {
            BufferedImage image = ImageIO.read(new ByteArrayInputStream(imageData));
            if (image == null) {
                return new AnalysisResult(ImageModerationStatus.ERROR, 0.0,
                        Collections.emptyList(), "Could not decode image");
            }
            return classify(image);
        } catch (IOException e) {
            logger.error("Local CLIP image read error: {}", e.getMessage());
            return new AnalysisResult(ImageModerationStatus.ERROR, 0.0,
                    Collections.emptyList(), "Image read error: " + e.getMessage());
        } catch (OrtException e) {
            logger.error("Local CLIP inference error: {}", e.getMessage());
            return new AnalysisResult(ImageModerationStatus.ERROR, 0.0,
                    Collections.emptyList(), "CLIP inference error: " + e.getMessage());
        }
    }

    public boolean isModelReady() {
        return modelReady;
    }

    public String engineName() {
        return "Edge CLIP ONNX";
    }

    private Path resolveVisionModelPath() {
        String userDir = System.getProperty("user.dir", ".");
        Path[] candidates = {
                Path.of(visionModelPath),
                Path.of(userDir, visionModelPath),
                Path.of(userDir, "backend", visionModelPath),
                Path.of("backend", visionModelPath),
        };
        for (Path candidate : candidates) {
            Path abs = candidate.toAbsolutePath().normalize();
            if (Files.isRegularFile(abs)) {
                return abs;
            }
        }
        return Path.of(visionModelPath).toAbsolutePath().normalize();
    }

    // =========================================================================
    // INFERENCE
    // =========================================================================

    private AnalysisResult classify(BufferedImage image) throws OrtException {
        float[] imageEmbedding = encodeImage(image);
        normalize(imageEmbedding);

        LabelEmbedding winner = null;
        double winnerScore = Double.NEGATIVE_INFINITY;
        Map<ImageContentCategory, Double> bestPerCategory = new EnumMap<>(ImageContentCategory.class);
        Map<ImageContentCategory, String> labelByCategory = new EnumMap<>(ImageContentCategory.class);

        for (LabelEmbedding label : labelEmbeddings) {
            if (label.category() == ImageContentCategory.SPAM) {
                continue;
            }
            double score = cosineSimilarity(imageEmbedding, label.embedding());
            if (score > winnerScore) {
                winnerScore = score;
                winner = label;
            }
            if (label.category() != null) {
                Double prev = bestPerCategory.get(label.category());
                if (prev == null || score >= prev) {
                    bestPerCategory.put(label.category(), score);
                    labelByCategory.put(label.category(), label.text());
                }
            }
        }

        if (winner == null) {
            return new AnalysisResult(ImageModerationStatus.ERROR, 0.0,
                    List.of(), "CLIP produced no label scores.");
        }

        if (winner.category() == null) {
            return new AnalysisResult(
                    ImageModerationStatus.SAFE,
                    winnerScore,
                    List.of(),
                    String.format("No policy violations detected (best match: safe %.1f%%).",
                            winnerScore * 100));
        }

        ImageContentCategory category = winner.category();
        double threshold = category == ImageContentCategory.WEAPONS
                ? FLAG_THRESHOLD_WEAPONS
                : FLAG_THRESHOLD;
        double safeScore = safeAnchor != null
                ? cosineSimilarity(imageEmbedding, safeAnchor.embedding())
                : 0.0;

        if (winnerScore < threshold) {
            return new AnalysisResult(
                    ImageModerationStatus.SAFE,
                    safeScore,
                    List.of(),
                    String.format("Below threshold (top %s %.1f%%, safe %.1f%%).",
                            category.name(), winnerScore * 100, safeScore * 100));
        }

        ImageModerationStatus status = winnerScore >= REJECT_THRESHOLD
                ? ImageModerationStatus.REJECTED
                : ImageModerationStatus.FLAGGED;

        String reason = String.format(
                "[Edge CLIP] %s detected: %s (%.1f%%, safe %.1f%%).",
                category.name(),
                labelByCategory.getOrDefault(category, winner.text()),
                winnerScore * 100,
                safeScore * 100);

        return new AnalysisResult(status, winnerScore, List.of(category), reason);
    }

    private float[] encodeImage(BufferedImage source) throws OrtException {
        BufferedImage rgb = toRgb224(source);
        float[] chw = buildNormalizedTensor(rgb);

        try (OnnxTensor input = OnnxTensor.createTensor(
                ortEnv, FloatBuffer.wrap(chw), new long[] {1, 3, INPUT_SIZE, INPUT_SIZE})) {
            try (OrtSession.Result result = ortSession.run(Map.of("pixel_values", input))) {
                Object value = result.get(0).getValue();
                if (value instanceof float[][] batch) {
                    return batch[0].clone();
                }
                throw new IllegalStateException("Unexpected ONNX output type: " + value.getClass());
            }
        }
    }

    private static BufferedImage toRgb224(BufferedImage source) {
        BufferedImage rgb = new BufferedImage(INPUT_SIZE, INPUT_SIZE, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = rgb.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
        g.drawImage(source, 0, 0, INPUT_SIZE, INPUT_SIZE, null);
        g.dispose();
        return rgb;
    }

    private static float[] buildNormalizedTensor(BufferedImage rgb) {
        float[] chw = new float[3 * INPUT_SIZE * INPUT_SIZE];
        int planeSize = INPUT_SIZE * INPUT_SIZE;
        for (int y = 0; y < INPUT_SIZE; y++) {
            for (int x = 0; x < INPUT_SIZE; x++) {
                int pixel = rgb.getRGB(x, y);
                float r = ((pixel >> 16) & 0xFF) / 255f;
                float g = ((pixel >> 8) & 0xFF) / 255f;
                float b = (pixel & 0xFF) / 255f;
                int idx = y * INPUT_SIZE + x;
                chw[idx] = (r - MEAN[0]) / STD[0];
                chw[planeSize + idx] = (g - MEAN[1]) / STD[1];
                chw[2 * planeSize + idx] = (b - MEAN[2]) / STD[2];
            }
        }
        return chw;
    }

    private static double cosineSimilarity(float[] a, float[] b) {
        double dot = 0, normA = 0, normB = 0;
        for (int i = 0; i < a.length; i++) {
            dot += a[i] * b[i];
            normA += a[i] * a[i];
            normB += b[i] * b[i];
        }
        if (normA == 0 || normB == 0) return 0;
        return dot / (Math.sqrt(normA) * Math.sqrt(normB));
    }

    private static void normalize(float[] vector) {
        double norm = 0;
        for (float v : vector) norm += v * v;
        norm = Math.sqrt(norm);
        if (norm == 0) return;
        for (int i = 0; i < vector.length; i++) vector[i] /= (float) norm;
    }

    // =========================================================================
    // MODEL ASSETS
    // =========================================================================

    private List<LabelEmbedding> loadLabelEmbeddings() throws IOException {
        ClassPathResource resource = new ClassPathResource(embeddingsClasspath);
        if (!resource.exists()) {
            throw new IOException("Missing CLIP label embeddings: " + embeddingsClasspath);
        }
        try (InputStream in = resource.getInputStream()) {
            JsonNode root = objectMapper.readTree(in);
            JsonNode labels = root.get("labels");
            List<LabelEmbedding> loaded = new ArrayList<>();
            for (JsonNode node : labels) {
                String text = node.get("text").asText();
                String categoryRaw = node.hasNonNull("category") ? node.get("category").asText() : null;
                ImageContentCategory category = categoryRaw != null
                        ? ImageContentCategory.valueOf(categoryRaw)
                        : null;
                if (category == ImageContentCategory.SPAM) {
                    continue;
                }
                float[] embedding = new float[node.get("embedding").size()];
                for (int i = 0; i < embedding.length; i++) {
                    embedding[i] = (float) node.get("embedding").get(i).asDouble();
                }
                normalize(embedding);
                loaded.add(new LabelEmbedding(text, category, embedding));
            }
            loaded.sort(Comparator.comparing(LabelEmbedding::text));
            return List.copyOf(loaded);
        }
    }

    // =========================================================================
    // RESULT TYPE
    // =========================================================================

    private record LabelEmbedding(String text, ImageContentCategory category, float[] embedding) {}

    public record AnalysisResult(
            ImageModerationStatus status,
            double confidence,
            List<ImageContentCategory> categories,
            String reason) {}
}
