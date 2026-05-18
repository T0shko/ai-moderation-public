package com.example.aimoderation.service;

import com.example.aimoderation.model.*;
import com.example.aimoderation.repository.ImageModerationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.*;

/**
 * TriGuard Vision Ensemble — dual CLIP layers, any-hit detection:
 *   1. Cloud CLIP (Hugging Face NSFW, optional)
 *   2. Edge CLIP ONNX (self-hosted zero-shot)
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
        logger.info("TriGuard moderation for: {}", safeFilename);

        String validationError = validateFile(imageData, contentType, safeFilename);
        if (validationError != null) {
            return buildErrorResult(safeFilename, validationError);
        }

        String imageHash = calculateHash(imageData);

        HuggingFaceImageService.ImageAnalysisResult cloudResult =
                huggingFaceService.analyzeImage(imageData, safeFilename);
        LocalImageAnalysisService.AnalysisResult edgeResult =
                localImageAnalysisService.analyze(imageData);

        List<String> clipLabels = cloudResult.detectedLabels() != null
                ? new ArrayList<>(cloudResult.detectedLabels())
                : new ArrayList<>();
        if (edgeResult.status() != ImageModerationStatus.ERROR && edgeResult.confidence() > 0) {
            clipLabels.add(String.format("Edge CLIP: %.1f%%", edgeResult.confidence() * 100));
        }

        TriGuardVisionEnsemble.MergedResult merged = TriGuardVisionEnsemble.merge(
                cloudResult, edgeResult, clipLabels);

        ImageModerationResult result = buildModerationResult(
                safeFilename, imageHash, merged, uploadedBy);
        return persistFreshAnalysis(result, safeFilename);
    }

    /** Wipe all stored image verdicts (admin / testing). */
    @Transactional
    public long clearAllResults() {
        long count = imageModerationRepository.count();
        imageModerationRepository.deleteAllInBatch();
        logger.info("Cleared {} image moderation records from database", count);
        return count;
    }

    public Map<String, Long> getStats() {
        Map<String, Long> stats = new HashMap<>();
        for (ImageModerationStatus status : ImageModerationStatus.values()) {
            stats.put(status.name(), imageModerationRepository.countByStatus(status));
        }
        return stats;
    }

    public static String engineName() {
        return TriGuardVisionEnsemble.ENGINE_NAME;
    }

    private ImageModerationResult buildModerationResult(
            String filename, String hash, TriGuardVisionEnsemble.MergedResult merged, User uploadedBy) {
        ImageModerationResult result = new ImageModerationResult(filename, merged.status());
        result.setImageHash(hash);
        result.setConfidenceScore(merged.confidence());
        result.setDetectedCategories(categoriesToString(merged.categories()));
        result.setModerationReason(merged.reason());
        result.setClipLabels(merged.clipLabels());
        result.setTriGuardLayers(formatLayerVotes(merged.layerVotes()));
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

    /** Every scan is a new DB row + fresh inference (no hash reuse). */
    private ImageModerationResult persistFreshAnalysis(
            ImageModerationResult result, String requestedFilename) {
        result.setImageUrl(requestedFilename != null ? requestedFilename : result.getImageUrl());
        ImageModerationResult saved = imageModerationRepository.save(result);
        logger.info("Fresh image analysis id={} status={} hash={}",
                saved.getId(), saved.getStatus(), saved.getImageHash());
        return withTransientFields(cloneForResponse(saved, requestedFilename), result);
    }

    private ImageModerationResult withTransientFields(ImageModerationResult target, ImageModerationResult source) {
        target.setClipLabels(source.getClipLabels());
        target.setTriGuardLayers(source.getTriGuardLayers());
        return target;
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
        result.setTriGuardLayers(source.getTriGuardLayers() != null ? source.getTriGuardLayers() : List.of());
        result.setUploadedBy(source.getUploadedBy());
        result.setCreatedAt(source.getCreatedAt());
        result.setModeratedAt(source.getModeratedAt());
        return result;
    }

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
            if (ALLOWED_FORMATS.contains(normalized)) return normalized;
        }
        if (filename == null) return "";
        String lower = filename.toLowerCase();
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
        if (lower.endsWith(".png")) return "image/png";
        if (lower.endsWith(".gif")) return "image/gif";
        if (lower.endsWith(".webp")) return "image/webp";
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

    private List<String> formatLayerVotes(List<TriGuardVisionEnsemble.LayerVote> votes) {
        if (votes == null) return List.of();
        return votes.stream()
                .map(v -> String.format("%s: %s (%.0f%%)%s",
                        v.layer(),
                        v.status().name(),
                        v.confidence() * 100,
                        v.category() != null ? " " + v.category().name() : ""))
                .toList();
    }
}
