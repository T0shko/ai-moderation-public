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

    private static final String HF_API_BASE = "https://api-inference.huggingface.co/models/";

    // CLIP model for zero-shot image classification
    private static final String CLIP_MODEL = "openai/clip-vit-large-patch14";

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
        LABEL_TO_CATEGORY.put("spam or advertising overlay", "SPAM");
        LABEL_TO_CATEGORY.put("safe everyday content", null); // anchor for "nothing wrong"
    }

    // Threshold: if a dangerous label scores above this relative to "safe", flag it
    private static final double FLAG_THRESHOLD = 0.15;
    private static final double REJECT_THRESHOLD = 0.35;

    @Value("${huggingface.api.token:}")
    private String hfApiToken;

    @Value("${huggingface.api.enabled:true}")
    private boolean hfEnabled;

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

        // Check filename for obvious dangerous content
        FilenameAnalysis filenameResult = analyzeFilename(filename);
        if (filenameResult.isSuspicious) {
            detectedCategories.addAll(filenameResult.categories);
            reasons.append(filenameResult.reason).append(" ");
            maxConfidence = Math.max(maxConfidence, 0.7);
        }

        // If HF API is not configured, use filename analysis only
        if (hfApiToken == null || hfApiToken.isEmpty() || !hfEnabled) {
            logger.warn("Hugging Face API token not configured - using filename analysis only");

            if (detectedCategories.isEmpty()) {
                // No suspicious filename — let local algorithm handle analysis
                return new ImageAnalysisResult(
                    ImageAnalysisStatus.SAFE,
                    0.0,
                    detectedCategories,
                    detectedLabels,
                    "HuggingFace API not configured. Relying on local analysis."
                );
            }

            return new ImageAnalysisResult(
                ImageAnalysisStatus.REJECTED,
                maxConfidence,
                detectedCategories,
                detectedLabels,
                reasons.toString().trim()
            );
        }

        try {
            // Single CLIP zero-shot call covering all categories
            List<ClassificationResult> results = classifyImageZeroShot(imageData);

            for (ClassificationResult result : results) {
                detectedLabels.add(result.label + " (" + String.format("%.1f%%", result.score * 100) + ")");

                String category = LABEL_TO_CATEGORY.get(result.label);
                if (category != null && result.score >= FLAG_THRESHOLD) {
                    if (!detectedCategories.contains(category)) {
                        detectedCategories.add(category);
                    }
                    maxConfidence = Math.max(maxConfidence, result.score);
                    reasons.append(category).append(" detected: ").append(result.label)
                           .append(" (").append(String.format("%.1f%%", result.score * 100)).append("). ");
                }
            }

        } catch (Exception e) {
            logger.error("Hugging Face CLIP API error: {}", e.getMessage());
            reasons.append("AI analysis error: ").append(e.getMessage()).append(". ");

            return new ImageAnalysisResult(
                ImageAnalysisStatus.FLAGGED,
                0.5,
                detectedCategories,
                detectedLabels,
                reasons.toString() + "Manual review recommended."
            );
        }

        // Determine final status
        ImageAnalysisStatus status;
        if (!detectedCategories.isEmpty()) {
            if (maxConfidence >= REJECT_THRESHOLD) {
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
        List<String> categories = new ArrayList<>();
        StringBuilder reason = new StringBuilder();

        String[] weaponNames = {"makarov", "glock", "ak47", "ak-47", "m16", "ar15", "ar-15",
                                "beretta", "colt", "kalashnikov", "uzi", "mp5", "rifle",
                                "pistol", "gun", "weapon", "knife", "sword"};
        for (String weapon : weaponNames) {
            if (lowerFilename.contains(weapon)) {
                categories.add("WEAPON");
                reason.append("Filename contains weapon reference: ").append(weapon).append(". ");
                break;
            }
        }

        String[] explicitNames = {"nsfw", "xxx", "porn", "nude", "naked", "sex"};
        for (String explicit : explicitNames) {
            if (lowerFilename.contains(explicit)) {
                categories.add("ADULT");
                reason.append("Filename suggests adult content. ");
                break;
            }
        }

        String[] violenceNames = {"gore", "blood", "death", "kill", "murder", "corpse"};
        for (String violence : violenceNames) {
            if (lowerFilename.contains(violence)) {
                categories.add("VIOLENCE");
                reason.append("Filename suggests violent content. ");
                break;
            }
        }

        return new FilenameAnalysis(!categories.isEmpty(), categories, reason.toString());
    }

    /**
     * Call CLIP zero-shot image classification via HuggingFace Inference API.
     * Sends the image + all candidate labels in one request.
     */
    @SuppressWarnings("unchecked")
    private List<ClassificationResult> classifyImageZeroShot(byte[] imageData) {
        String url = HF_API_BASE + CLIP_MODEL;

        String base64Image = Base64.getEncoder().encodeToString(imageData);
        List<String> candidateLabels = new ArrayList<>(LABEL_TO_CATEGORY.keySet());

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("image", base64Image);
        body.put("parameters", Map.of("candidate_labels", candidateLabels));

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setBearerAuth(hfApiToken);

        HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

        try {
            ResponseEntity<Map> response = restTemplate.exchange(
                url, HttpMethod.POST, request, Map.class
            );

            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                Map<String, Object> responseBody = response.getBody();
                List<String> labels = (List<String>) responseBody.get("labels");
                List<Number> scores = (List<Number>) responseBody.get("scores");

                List<ClassificationResult> results = new ArrayList<>();
                if (labels != null && scores != null) {
                    for (int i = 0; i < labels.size(); i++) {
                        results.add(new ClassificationResult(labels.get(i), scores.get(i).doubleValue()));
                    }
                }
                return results;
            }
        } catch (Exception e) {
            logger.warn("CLIP zero-shot classification failed: {}", e.getMessage());
        }

        return Collections.emptyList();
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
