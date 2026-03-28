package com.example.aimoderation.service;

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
 * Free tier: 300 requests/hour (requires HF API token)
 * 
 * Uses multiple models for comprehensive content detection:
 * - NSFW detection
 * - Object/weapon classification
 * - Violence detection
 */
@Service
public class HuggingFaceImageService {
    
    private static final Logger logger = LoggerFactory.getLogger(HuggingFaceImageService.class);
    
    private static final String HF_API_BASE = "https://api-inference.huggingface.co/models/";
    
    // Pre-trained models for different detection tasks
    private static final String NSFW_MODEL = "Falconsai/nsfw_image_detection";
    private static final String OBJECT_MODEL = "google/vit-base-patch16-224";
    
    // Dangerous object keywords to flag
    private static final Set<String> WEAPON_KEYWORDS = Set.of(
        "rifle", "gun", "pistol", "revolver", "firearm", "assault rifle", 
        "machine gun", "shotgun", "handgun", "weapon", "ak47", "ak-47",
        "knife", "sword", "dagger", "blade", "machete",
        "bomb", "grenade", "explosive", "missile",
        "tank", "military vehicle"
    );
    
    private static final Set<String> VIOLENCE_KEYWORDS = Set.of(
        "blood", "gore", "corpse", "dead body", "violence", "murder",
        "injury", "wound", "death"
    );
    
    @Value("${huggingface.api.token:}")
    private String hfApiToken;
    
    @Value("${huggingface.api.enabled:true}")
    private boolean hfEnabled;
    
    private final RestTemplate restTemplate;
    
    public HuggingFaceImageService() {
        this.restTemplate = new RestTemplate();
    }
    
    /**
     * Analyze an image using Hugging Face AI models.
     * Returns analysis results with detected categories and confidence.
     */
    public ImageAnalysisResult analyzeImage(byte[] imageData, String filename) {
        logger.info("Starting Hugging Face AI analysis for: {}", filename);
        
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
            reasons.append("AI analysis unavailable (no API token). ");
            
            // Default to FLAGGED for human review when AI is not available
            return new ImageAnalysisResult(
                detectedCategories.isEmpty() ? ImageAnalysisStatus.FLAGGED : ImageAnalysisStatus.REJECTED,
                maxConfidence > 0 ? maxConfidence : 0.5,
                detectedCategories,
                detectedLabels,
                reasons.toString() + "Manual review required."
            );
        }
        
        try {
            // 1. Run NSFW detection
            List<ClassificationResult> nsfwResults = classifyImage(imageData, NSFW_MODEL);
            for (ClassificationResult result : nsfwResults) {
                detectedLabels.add(result.label + " (" + String.format("%.1f%%", result.score * 100) + ")");
                
                if (result.label.toLowerCase().contains("nsfw") && result.score > 0.5) {
                    detectedCategories.add("ADULT");
                    maxConfidence = Math.max(maxConfidence, result.score);
                    reasons.append("NSFW content detected (").append(String.format("%.1f%%", result.score * 100)).append("). ");
                }
            }
            
            // 2. Run object classification for weapons/violence detection
            List<ClassificationResult> objectResults = classifyImage(imageData, OBJECT_MODEL);
            for (ClassificationResult result : objectResults) {
                String label = result.label.toLowerCase();
                detectedLabels.add(result.label + " (" + String.format("%.1f%%", result.score * 100) + ")");
                
                // Check for weapon-related objects
                for (String weaponKeyword : WEAPON_KEYWORDS) {
                    if (label.contains(weaponKeyword) && result.score > 0.3) {
                        detectedCategories.add("WEAPON");
                        maxConfidence = Math.max(maxConfidence, result.score);
                        reasons.append("Weapon detected: ").append(result.label)
                               .append(" (").append(String.format("%.1f%%", result.score * 100)).append("). ");
                        break;
                    }
                }
                
                // Check for violence-related content
                for (String violenceKeyword : VIOLENCE_KEYWORDS) {
                    if (label.contains(violenceKeyword) && result.score > 0.3) {
                        detectedCategories.add("VIOLENCE");
                        maxConfidence = Math.max(maxConfidence, result.score);
                        reasons.append("Violence indicator: ").append(result.label)
                               .append(" (").append(String.format("%.1f%%", result.score * 100)).append("). ");
                        break;
                    }
                }
            }
            
        } catch (Exception e) {
            logger.error("Hugging Face API error: {}", e.getMessage());
            reasons.append("AI analysis error: ").append(e.getMessage()).append(". ");
            
            // On API error, flag for manual review
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
            if (maxConfidence > 0.7) {
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
        
        // Check for weapon-related filenames
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
        
        // Check for explicit content filenames
        String[] explicitNames = {"nsfw", "xxx", "porn", "nude", "naked", "sex"};
        for (String explicit : explicitNames) {
            if (lowerFilename.contains(explicit)) {
                categories.add("ADULT");
                reason.append("Filename suggests adult content. ");
                break;
            }
        }
        
        // Check for violence-related filenames
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
     * Call Hugging Face Inference API for image classification.
     */
    private List<ClassificationResult> classifyImage(byte[] imageData, String model) {
        String url = HF_API_BASE + model;
        
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_OCTET_STREAM);
        headers.setBearerAuth(hfApiToken);
        
        HttpEntity<byte[]> request = new HttpEntity<>(imageData, headers);
        
        try {
            ResponseEntity<List> response = restTemplate.exchange(
                url, HttpMethod.POST, request, List.class
            );
            
            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                List<ClassificationResult> results = new ArrayList<>();
                for (Object item : response.getBody()) {
                    if (item instanceof Map) {
                        Map<String, Object> map = (Map<String, Object>) item;
                        String label = (String) map.get("label");
                        Number score = (Number) map.get("score");
                        if (label != null && score != null) {
                            results.add(new ClassificationResult(label, score.doubleValue()));
                        }
                    }
                }
                return results;
            }
        } catch (Exception e) {
            logger.warn("Classification failed for model {}: {}", model, e.getMessage());
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
