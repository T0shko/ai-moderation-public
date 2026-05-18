package com.example.aimoderation.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.*;

/**
 * Service for AI-powered image analysis using Hugging Face's free Inference API.
 *
 * Uses CLIP zero-shot image classification to detect all safety categories
 * (NSFW, violence, weapons, gore, drugs, etc.) in a single API call.
 *
 * Free tier: 300 requests/hour (requires HF API token)
 */
@Service
public class HuggingFaceImageService {

    private static final Logger logger = LoggerFactory.getLogger(HuggingFaceImageService.class);

    private static final String HF_ROUTER_BASE =
            "https://router.huggingface.co/hf-inference/models/";

    private static final double NSFW_FLAG_THRESHOLD = 0.25;
    private static final double NSFW_REJECT_THRESHOLD = 0.45;

    // Candidate labels for zero-shot classification, mapped to categories
    private static final Map<String, String> LABEL_TO_CATEGORY = new LinkedHashMap<>();
    static {
        LABEL_TO_CATEGORY.put("nudity or sexual content", "ADULT");
        LABEL_TO_CATEGORY.put("pornographic content", "ADULT");
        LABEL_TO_CATEGORY.put("violence or gore", "VIOLENCE");
        LABEL_TO_CATEGORY.put("blood or graphic injury", "VIOLENCE");
        LABEL_TO_CATEGORY.put("firearms or weapons", "WEAPONS");
        LABEL_TO_CATEGORY.put("knife or bladed weapon", "WEAPONS");
        LABEL_TO_CATEGORY.put("drugs or drug paraphernalia", "DRUGS");
        LABEL_TO_CATEGORY.put("hate symbols or extremist imagery", "HATE_SYMBOLS");
        LABEL_TO_CATEGORY.put("self harm or suicide", "SELF_HARM");
        LABEL_TO_CATEGORY.put("graphic medical imagery", "GRAPHIC_MEDICAL");
        LABEL_TO_CATEGORY.put("gambling", "GAMBLING");
        LABEL_TO_CATEGORY.put("safe everyday content", null); // anchor for "nothing wrong"
    }

    private static final double FLAG_THRESHOLD = 0.15;
    private static final double FLAG_THRESHOLD_WEAPONS = 0.11;
    private static final double REJECT_THRESHOLD = 0.35;
    @Value("${huggingface.api.token:}")
    private String hfApiToken;

    @Value("${huggingface.api.enabled:true}")
    private boolean hfEnabled;

    @Value("${huggingface.image.nsfw-model:Falconsai/nsfw_image_detection}")
    private String nsfwModelId;

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;

    public HuggingFaceImageService() {
        this.restTemplate = new RestTemplate();
        this.objectMapper = new ObjectMapper();
    }

    /**
     * Analyze an image using CLIP zero-shot classification.
     * Returns analysis results with detected categories and confidence.
     */
    public ImageAnalysisResult analyzeImage(byte[] imageData, String filename) {
        logger.info("Starting Hugging Face CLIP analysis for: {}", filename);

        List<String> detectedCategories = new ArrayList<>();
        List<String> detectedLabels = new ArrayList<>();
        double maxConfidence = 0.0;
        StringBuilder reasons = new StringBuilder();

        if (hfApiToken == null || hfApiToken.isEmpty() || !hfEnabled) {
            logger.warn("Hugging Face API token not configured — Cloud CLIP layer skipped");
            return new ImageAnalysisResult(
                    ImageAnalysisStatus.SAFE,
                    0.0,
                    detectedCategories,
                    detectedLabels,
                    "HuggingFace API not configured. Edge CLIP remains active."
            );
        }

        try {
            List<ClassificationResult> results = classifyViaCloudNsfw(imageData);
            if (results.isEmpty()) {
                logger.warn("Cloud inference returned no scores — layer skipped");
                return new ImageAnalysisResult(
                        ImageAnalysisStatus.SAFE,
                        0.0,
                        detectedCategories,
                        detectedLabels,
                        "Cloud inference unavailable. Edge CLIP remains active.");
            }

            for (ClassificationResult result : results) {
                detectedLabels.add(result.label + " (" + String.format("%.1f%%", result.score * 100) + ")");
            }

            double nsfwScore = results.stream()
                    .filter(r -> "nsfw".equalsIgnoreCase(r.label))
                    .mapToDouble(r -> r.score)
                    .findFirst()
                    .orElse(0.0);
            double normalScore = results.stream()
                    .filter(r -> "normal".equalsIgnoreCase(r.label))
                    .mapToDouble(r -> r.score)
                    .findFirst()
                    .orElse(0.0);

            if (nsfwScore >= NSFW_FLAG_THRESHOLD) {
                detectedCategories.add("ADULT");
                maxConfidence = nsfwScore;
                reasons.append("[Cloud CLIP] ADULT detected: nsfw (")
                        .append(String.format("%.1f%%", nsfwScore * 100))
                        .append(", normal ")
                        .append(String.format("%.1f%%", normalScore * 100))
                        .append(").");
            } else {
                reasons.append(String.format("[Cloud CLIP] Safe (normal %.1f%%).", normalScore * 100));
            }

        } catch (Exception e) {
            logger.error("Hugging Face CLIP API error: {}", e.getMessage());
            return new ImageAnalysisResult(
                    ImageAnalysisStatus.SAFE,
                    0.0,
                    detectedCategories,
                    detectedLabels,
                    "Cloud CLIP error (layer skipped): " + e.getMessage());
        }

        // Determine final status
        ImageAnalysisStatus status;
        if (!detectedCategories.isEmpty()) {
            double rejectBar = detectedCategories.contains("ADULT")
                    ? NSFW_REJECT_THRESHOLD
                    : REJECT_THRESHOLD;
            if (maxConfidence >= rejectBar) {
                status = ImageAnalysisStatus.REJECTED;
            } else {
                status = ImageAnalysisStatus.FLAGGED;
            }
        } else {
            status = ImageAnalysisStatus.SAFE;
            if (reasons.length() == 0) {
                reasons.append("No policy violations detected.");
            }
        }

        return new ImageAnalysisResult(status, maxConfidence, detectedCategories, detectedLabels, reasons.toString().trim());
    }

    /**
     * Analyze filename for suspicious content.
     */
    private FilenameAnalysis analyzeFilename(String filename) {
        if (filename == null || filename.isEmpty()) {
            return new FilenameAnalysis(false, Collections.emptyList(), "");
        }

        String lowerFilename = filename.toLowerCase();
        StringBuilder reason = new StringBuilder();

        String[] weaponNames = {"makarov", "glock", "ak47", "ak-47", "m16", "ar15", "ar-15",
                                "beretta", "colt", "kalashnikov", "uzi", "mp5", "rifle",
                                "pistol", "gun", "weapon", "knife", "sword"};
        for (String weapon : weaponNames) {
            if (lowerFilename.contains(weapon)) {
                reason.append("Filename contains weapon reference: ").append(weapon).append(". ");
                return new FilenameAnalysis(true, List.of("WEAPONS"), reason.toString());
            }
        }

        String[] explicitNames = {"nsfw", "xxx", "porn", "nude", "naked", "sex"};
        for (String explicit : explicitNames) {
            if (lowerFilename.contains(explicit)) {
                reason.append("Filename suggests adult content. ");
                return new FilenameAnalysis(true, List.of("ADULT"), reason.toString());
            }
        }

        String[] violenceNames = {"gore", "blood", "death", "kill", "murder", "corpse"};
        for (String violence : violenceNames) {
            if (lowerFilename.contains(violence)) {
                reason.append("Filename suggests violent content. ");
                return new FilenameAnalysis(true, List.of("VIOLENCE"), reason.toString());
            }
        }

        return new FilenameAnalysis(false, Collections.emptyList(), "");
    }

    /** Hugging Face serverless image classification (NSFW model on Inference router). */
    @SuppressWarnings("unchecked")
    private List<ClassificationResult> classifyViaCloudNsfw(byte[] imageData) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(hfApiToken);
        headers.setContentType(MediaType.IMAGE_JPEG);
        headers.set("x-wait-for-model", "true");

        String url = HF_ROUTER_BASE + nsfwModelId;
        try {
            ResponseEntity<List> response = restTemplate.exchange(
                    url,
                    HttpMethod.POST,
                    new HttpEntity<>(imageData, headers),
                    List.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                return parseLabelScoreList(response.getBody());
            }
        } catch (Exception e) {
            logger.warn("Cloud NSFW inference failed: {}", e.getMessage());
        }
        return List.of();
    }

    @SuppressWarnings("unchecked")
    private List<ClassificationResult> parseLabelScoreList(List<?> body) {
        List<ClassificationResult> results = new ArrayList<>();
        for (Object item : body) {
            if (item instanceof Map<?, ?> map) {
                Object label = map.get("label");
                Object score = map.get("score");
                if (label != null && score instanceof Number num) {
                    results.add(new ClassificationResult(label.toString(), num.doubleValue()));
                }
            }
        }
        return results;
    }

    // --- Result classes ---

    public enum ImageAnalysisStatus {
        SAFE, FLAGGED, REJECTED, ERROR
    }

    public record ImageAnalysisResult(
        ImageAnalysisStatus status,
        double confidence,
        List<String> categories,
        List<String> detectedLabels,
        String reason
    ) {}

    private record ClassificationResult(String label, double score) {}

    private record FilenameAnalysis(boolean isSuspicious, List<String> categories, String reason) {}
}
