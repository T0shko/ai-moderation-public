package com.example.aimoderation.service;

import com.example.aimoderation.model.*;
import com.example.aimoderation.repository.ImageModerationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.*;

/**
 * Orchestrates the two-layer image moderation ensemble:
 *
 *   Layer 1 — HuggingFace CLIP zero-shot (optional, needs API token)
 *   Layer 2 — LocalImageAnalysisService spatial-grid heuristics (always available)
 *
 * If ANY layer signals a violation → image is blocked/flagged.
 */
@Service
public class ImageModerationService {

    private static final Logger logger = LoggerFactory.getLogger(ImageModerationService.class);

    @Autowired
    private ImageModerationRepository imageModerationRepository;

    @Autowired
    private HuggingFaceImageService huggingFaceService;

    @Autowired
    private LocalImageAnalysisService localImageAnalysisService;

    @Value("${moderation.image.max-size:10485760}")
    private long maxImageSize;

    private static final Set<String> ALLOWED_FORMATS = Set.of(
            "image/jpeg", "image/jpg", "image/png", "image/gif", "image/webp"
    );

    // =========================================================================
    // PUBLIC API
    // =========================================================================

    public ImageModerationResult moderateImage(MultipartFile file, User uploadedBy) {
        try {
            return moderateImage(file.getBytes(), file.getOriginalFilename(), file.getContentType(), uploadedBy);

        } catch (IOException e) {
            logger.error("Error reading image: {}", e.getMessage());
            return buildErrorResult(file.getOriginalFilename(), "Error reading image: " + e.getMessage());
        }
    }

    public ImageModerationResult moderateImage(
            byte[] imageData,
            String filename,
            String contentType,
            User uploadedBy) {
        String safeFilename = filename != null ? filename : "upload";
        logger.info("Starting moderation for image: {}", safeFilename);

        String validationError = validateFile(imageData, contentType, safeFilename);
        if (validationError != null) {
            return buildErrorResult(safeFilename, validationError);
        }

        String imageHash = calculateHash(imageData);

        Optional<ImageModerationResult> cached = imageModerationRepository.findByImageHash(imageHash);
        if (cached.isPresent()) {
            ImageModerationResult existing = cached.get();
            String cachedFilename = existing.getImageUrl();
            if (cachedFilename != null && cachedFilename.equals(safeFilename)) {
                logger.info("Cache hit for hash: {}", imageHash);
                return cloneForResponse(existing, safeFilename);
            }
            logger.info("Cache skipped for hash {}: filename changed ('{}' -> '{}')",
                    imageHash, cachedFilename, safeFilename);
        }

        HuggingFaceImageService.ImageAnalysisResult hfResult =
                huggingFaceService.analyzeImage(imageData, safeFilename);

        LocalImageAnalysisService.AnalysisResult localResult =
                localImageAnalysisService.analyze(imageData);

        EnsembleResult ensemble = mergeResults(hfResult, localResult);

        ImageModerationResult result = buildModerationResult(
                safeFilename, imageHash, ensemble, uploadedBy);
        return saveOrReuseExisting(result, safeFilename, imageHash);
    }

    public Map<String, Long> getStats() {
        Map<String, Long> stats = new HashMap<>();
        for (ImageModerationStatus status : ImageModerationStatus.values()) {
            stats.put(status.name(), imageModerationRepository.countByStatus(status));
        }
        return stats;
    }

    // =========================================================================
    // ENSEMBLE MERGE
    // =========================================================================

    /**
     * Combine HuggingFace and local analysis.
     * Ensemble rule: take the strictest status and union of all categories.
     */
    private EnsembleResult mergeResults(
            HuggingFaceImageService.ImageAnalysisResult hf,
            LocalImageAnalysisService.AnalysisResult local) {

        List<ImageContentCategory> categories = new ArrayList<>(local.categories());
        double maxConfidence = local.confidence();

        for (String cat : hf.categories()) {
            ImageContentCategory mapped = mapCategory(cat);
            if (mapped != null && !categories.contains(mapped)) categories.add(mapped);
        }
        maxConfidence = Math.max(maxConfidence, hf.confidence());

        ImageModerationStatus status;
        boolean anyRejected = hf.status() == HuggingFaceImageService.ImageAnalysisStatus.REJECTED
                || local.status() == ImageModerationStatus.REJECTED;
        boolean anyFlagged  = hf.status() == HuggingFaceImageService.ImageAnalysisStatus.FLAGGED
                || local.status() == ImageModerationStatus.FLAGGED;

        if (anyRejected || (!categories.isEmpty() && maxConfidence >= 0.7)) {
            status = ImageModerationStatus.REJECTED;
        } else if (anyFlagged || !categories.isEmpty()) {
            status = ImageModerationStatus.FLAGGED;
        } else {
            status = ImageModerationStatus.SAFE;
        }

        String reason = buildHumanReason(status, categories, hf, local);
        List<String> clipLabels = hf.detectedLabels() != null
                ? new ArrayList<>(hf.detectedLabels())
                : List.of();

        return new EnsembleResult(status, maxConfidence, categories, reason, clipLabels);
    }

    /**
     * Build a single human-readable reason aligned with the final ensemble status.
     * Omits layer boilerplate and never claims "no violations" when status is not SAFE.
     */
    private String buildHumanReason(
            ImageModerationStatus status,
            List<ImageContentCategory> categories,
            HuggingFaceImageService.ImageAnalysisResult hf,
            LocalImageAnalysisService.AnalysisResult local) {

        if (status == ImageModerationStatus.SAFE) {
            return "No policy violations detected.";
        }

        List<String> parts = new ArrayList<>();

        String hfReason = hf.reason();
        if (hfReason != null && !hfReason.isBlank() && isViolationHfReason(hfReason)) {
            parts.add(hfReason.trim());
        }

        String localReason = local.reason();
        if (localReason != null && localReason.contains("[LOCAL]")) {
            for (String segment : localReason.split("\\[LOCAL]")) {
                String trimmed = segment.trim();
                if (!trimmed.isEmpty() && !isSafeBoilerplate(trimmed)) {
                    parts.add("[LOCAL] " + trimmed);
                }
            }
        }

        if (parts.isEmpty() && !categories.isEmpty()) {
            for (ImageContentCategory category : categories) {
                parts.add(categoryViolationMessage(category, status));
            }
        }

        if (parts.isEmpty()) {
            return status == ImageModerationStatus.REJECTED
                    ? "Content blocked due to policy violation."
                    : "Content flagged for manual review.";
        }

        return String.join(" ", parts);
    }

    private boolean isViolationHfReason(String reason) {
        String lower = reason.toLowerCase();
        return !lower.contains("no policy violations")
                && !lower.contains("relying on local")
                && !lower.contains("api not configured");
    }

    private boolean isSafeBoilerplate(String text) {
        String lower = text.toLowerCase();
        return lower.contains("no violations detected")
                || lower.contains("no policy violations");
    }

    private String categoryViolationMessage(ImageContentCategory category, ImageModerationStatus status) {
        String action = status == ImageModerationStatus.REJECTED ? "blocked" : "flagged";
        return switch (category) {
            case ADULT -> "Adult or explicit content detected — image " + action + ".";
            case VIOLENCE -> "Violent content detected — image " + action + ".";
            case WEAPONS -> "Weapon-like content detected — image " + action + ".";
            case SPAM -> "Spam or text-overlay content detected — image " + action + ".";
            case DRUGS -> "Drug-related content detected — image " + action + ".";
            case HATE_SYMBOLS -> "Hate-symbol content detected — image " + action + ".";
            case SELF_HARM -> "Self-harm related content detected — image " + action + ".";
            case GRAPHIC_MEDICAL -> "Graphic medical content detected — image " + action + ".";
        };
    }

    /** Map raw category strings from HF to the ImageContentCategory enum */
    private ImageContentCategory mapCategory(String raw) {
        if (raw == null) return null;
        return switch (raw.toUpperCase()) {
            case "ADULT", "NSFW"                -> ImageContentCategory.ADULT;
            case "VIOLENCE"                     -> ImageContentCategory.VIOLENCE;
            case "WEAPONS", "WEAPON"            -> ImageContentCategory.WEAPONS;
            case "DRUGS"                        -> ImageContentCategory.DRUGS;
            case "HATE_SYMBOLS", "HATE"         -> ImageContentCategory.HATE_SYMBOLS;
            case "SPAM"                         -> ImageContentCategory.SPAM;
            case "SELF_HARM"                    -> ImageContentCategory.SELF_HARM;
            case "GRAPHIC_MEDICAL"              -> ImageContentCategory.GRAPHIC_MEDICAL;
            default -> {
                try { yield ImageContentCategory.valueOf(raw.toUpperCase()); }
                catch (IllegalArgumentException e) { yield null; }
            }
        };
    }

    // =========================================================================
    // RESULT BUILDERS
    // =========================================================================

    private ImageModerationResult buildModerationResult(
            String filename, String hash, EnsembleResult ensemble, User uploadedBy) {
        ImageModerationResult result = new ImageModerationResult(filename, ensemble.status());
        result.setImageHash(hash);
        result.setConfidenceScore(ensemble.confidence());
        result.setDetectedCategories(categoriesToString(ensemble.categories()));
        result.setModerationReason(ensemble.reason());
        result.setClipLabels(ensemble.clipLabels());
        result.setUploadedBy(uploadedBy);
        result.setModeratedAt(LocalDateTime.now());
        return result;
    }

    private ImageModerationResult buildErrorResult(String filename, String reason) {
        ImageModerationResult result = new ImageModerationResult(filename, ImageModerationStatus.ERROR);
        result.setModerationReason(reason);
        result.setModeratedAt(LocalDateTime.now());
        return result;
    }

    private ImageModerationResult saveOrReuseExisting(
            ImageModerationResult result,
            String requestedFilename,
            String imageHash) {
        try {
            return imageModerationRepository.save(result);
        } catch (DataIntegrityViolationException e) {
            logger.warn("Duplicate image hash detected, reusing existing result: {}", imageHash);
            return imageModerationRepository.findByImageHash(imageHash)
                    .map(existing -> cloneForResponse(existing, requestedFilename))
                    .orElseThrow(() -> e);
        }
    }

    private ImageModerationResult cloneForResponse(ImageModerationResult source, String requestedFilename) {
        ImageModerationResult result = new ImageModerationResult(
                requestedFilename != null ? requestedFilename : source.getImageUrl(),
                source.getStatus());
        result.setId(source.getId());
        result.setImageHash(source.getImageHash());
        result.setConfidenceScore(source.getConfidenceScore());
        result.setDetectedCategories(source.getDetectedCategories());
        result.setModerationReason(source.getModerationReason());
        result.setClipLabels(source.getClipLabels() != null ? source.getClipLabels() : List.of());
        result.setUploadedBy(source.getUploadedBy());
        result.setCreatedAt(source.getCreatedAt());
        result.setModeratedAt(source.getModeratedAt());
        return result;
    }

    // =========================================================================
    // UTILITIES
    // =========================================================================

    private String validateFile(byte[] imageData, String contentType, String filename) {
        if (imageData == null || imageData.length == 0) return "No file provided";

        String resolvedContentType = resolveContentType(contentType, filename);
        if (!ALLOWED_FORMATS.contains(resolvedContentType))
            return "Invalid format. Allowed: JPEG, PNG, GIF, WebP";
        if (imageData.length > maxImageSize) return "File exceeds maximum size";
        return null;
    }

    private String resolveContentType(String contentType, String filename) {
        if (contentType != null && !contentType.isBlank()) {
            String normalized = contentType.split(";")[0].trim().toLowerCase();
            if (ALLOWED_FORMATS.contains(normalized)) {
                return normalized;
            }
        }

        if (filename == null) {
            return "";
        }

        String lowerFilename = filename.toLowerCase();
        if (lowerFilename.endsWith(".jpg") || lowerFilename.endsWith(".jpeg")) {
            return "image/jpeg";
        }
        if (lowerFilename.endsWith(".png")) {
            return "image/png";
        }
        if (lowerFilename.endsWith(".gif")) {
            return "image/gif";
        }
        if (lowerFilename.endsWith(".webp")) {
            return "image/webp";
        }

        return "";
    }

    private String calculateHash(byte[] data) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(data);
            StringBuilder hex = new StringBuilder();
            for (byte b : hash) {
                String h = Integer.toHexString(0xff & b);
                if (h.length() == 1) hex.append('0');
                hex.append(h);
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            return UUID.randomUUID().toString();
        }
    }

    private String categoriesToString(List<ImageContentCategory> categories) {
        if (categories == null || categories.isEmpty()) return "";
        return categories.stream().map(Enum::name).reduce((a, b) -> a + "," + b).orElse("");
    }

    // =========================================================================
    // INTERNAL RECORD
    // =========================================================================

    private record EnsembleResult(
            ImageModerationStatus status,
            double confidence,
            List<ImageContentCategory> categories,
            String reason,
            List<String> clipLabels) {}
}
