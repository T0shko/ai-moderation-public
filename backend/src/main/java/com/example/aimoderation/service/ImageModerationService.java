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
 * Orchestrates the three-layer image moderation ensemble:
 *
 *   Layer 1 — Claude vision API      : semantic understanding of image content
 *   Layer 2 — HuggingFace API        : NSFW + object classification (optional, needs token)
 *   Layer 3 — LocalImageAnalysisService : custom spatial-grid pixel algorithm (always available)
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
            logger.info("Cache hit for hash: {}", imageHash);
            return cloneForResponse(cached.get(), safeFilename);
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
        StringBuilder reasons = new StringBuilder();
        double maxConfidence = local.confidence();

        // ── HuggingFace contribution ──────────────────────────────────────────
        for (String cat : hf.categories()) {
            ImageContentCategory mapped = mapCategory(cat);
            if (mapped != null && !categories.contains(mapped)) categories.add(mapped);
        }
        if (hf.reason() != null && !hf.reason().isBlank()) {
            reasons.append("[HF] ").append(hf.reason()).append(" ");
        }
        if (!hf.detectedLabels().isEmpty()) {
            reasons.append("Labels: ").append(String.join(", ", hf.detectedLabels())).append(" ");
        }
        maxConfidence = Math.max(maxConfidence, hf.confidence());

        // ── Local algorithm contribution ──────────────────────────────────────
        if (local.reason() != null && !local.reason().isBlank()) {
            reasons.append(local.reason());
        }

        // ── Final status ──────────────────────────────────────────────────────
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

        return new EnsembleResult(status, maxConfidence, categories, reasons.toString().trim());
    }

    /** Map raw category strings from Claude/HF to the ImageContentCategory enum */
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
            String reason) {}
}
