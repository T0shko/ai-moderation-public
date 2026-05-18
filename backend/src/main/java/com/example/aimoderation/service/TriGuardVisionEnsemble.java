package com.example.aimoderation.service;

import com.example.aimoderation.model.ImageContentCategory;
import com.example.aimoderation.model.ImageModerationStatus;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

/**
 * TriGuard Vision Ensemble — defensive OR policy: if any layer flags content,
 * the image is not SAFE.
 */
public final class TriGuardVisionEnsemble {

    public static final String ENGINE_NAME = "TriGuard Vision Ensemble";
    private static final double REJECT_CONFIDENCE = 0.35;
    private static final double MULTI_LAYER_BOOST = 0.12;

    private TriGuardVisionEnsemble() {}

    public record MergedResult(
            ImageModerationStatus status,
            double confidence,
            List<ImageContentCategory> categories,
            String reason,
            List<String> clipLabels,
            List<LayerVote> layerVotes) {}

    public record LayerVote(
            String layer,
            ImageModerationStatus status,
            double confidence,
            ImageContentCategory category,
            String reason) {}

    public static MergedResult merge(
            HuggingFaceImageService.ImageAnalysisResult cloudClip,
            LocalImageAnalysisService.AnalysisResult localClip,
            List<String> clipLabels) {

        List<LayerVote> votes = new ArrayList<>();
        votes.add(toVote("Cloud CLIP", cloudClip.status(), cloudClip.confidence(),
                primaryCategory(cloudClip.categories()), cloudClip.reason()));
        votes.add(toVote("Edge CLIP ONNX", localClip.status(), localClip.confidence(),
                primaryCategoryEnum(localClip.categories()), localClip.reason()));

        List<LayerVote> hits = votes.stream()
                .filter(TriGuardVisionEnsemble::isActionableViolation)
                .toList();

        boolean anyHit = !hits.isEmpty();
        boolean anyRejected = hits.stream()
                .anyMatch(v -> v.status() == ImageModerationStatus.REJECTED);
        long clipHitCount = hits.stream().filter(v -> isClipLayer(v.layer())).count();

        double maxHitConfidence = hits.stream()
                .mapToDouble(LayerVote::confidence)
                .max()
                .orElse(0.0);

        Optional<LayerVote> primary = selectPrimaryCategory(votes, hits);

        double ensembleConfidence = computeEnsembleConfidence(
                anyHit, maxHitConfidence, clipHitCount);

        boolean localError = localClip.status() == ImageModerationStatus.ERROR;
        boolean cloudUnavailable = cloudClip.reason() != null
                && cloudClip.reason().toLowerCase().contains("not configured");

        ImageModerationStatus status = resolveStatus(
                anyHit, anyRejected, maxHitConfidence, clipHitCount, localError, cloudUnavailable);

        List<ImageContentCategory> categories = resolveCategories(primary, hits, anyHit);

        if (status == ImageModerationStatus.SAFE) {
            ensembleConfidence = Math.max(cloudClip.confidence(), localClip.confidence());
            if (ensembleConfidence < 0.5) {
                ensembleConfidence = 0.85;
            }
        }

        String reason = buildReason(status, votes, hits, primary, clipHitCount, ensembleConfidence);

        return new MergedResult(status, ensembleConfidence, categories, reason, clipLabels, votes);
    }

    private static List<ImageContentCategory> resolveCategories(
            Optional<LayerVote> primary, List<LayerVote> hits, boolean anyHit) {
        if (primary.isPresent() && primary.get().category() != null) {
            return List.of(primary.get().category());
        }
        for (LayerVote hit : hits) {
            if (hit.category() != null) {
                return List.of(hit.category());
            }
        }
        if (anyHit) {
            return List.of(ImageContentCategory.OTHER);
        }
        return List.of();
    }

    private static boolean isViolation(LayerVote v) {
        return v.status() == ImageModerationStatus.REJECTED
                || v.status() == ImageModerationStatus.FLAGGED;
    }

    /** Ignore placeholder flags (0% confidence, API skip messages). */
    private static boolean isActionableViolation(LayerVote v) {
        if (!isViolation(v)) {
            return false;
        }
        if (v.confidence() <= 0.0) {
            return false;
        }
        String reason = v.reason() != null ? v.reason().toLowerCase() : "";
        if (reason.contains("not configured")
                || reason.contains("no scores")
                || reason.contains("skipped")
                || reason.contains("manual review recommended")) {
            return false;
        }
        return true;
    }

    /**
     * OR ensemble confidence: max of all violating layers; SAFE layers ignored.
     * Multiple CLIP hits boost score — never averaged down.
     */
    private static double computeEnsembleConfidence(
            boolean anyHit, double maxHitConfidence, long clipHitCount) {
        if (!anyHit) {
            return 0.0;
        }
        double conf = maxHitConfidence;
        if (clipHitCount >= 2) {
            conf = Math.min(0.99, conf + MULTI_LAYER_BOOST);
        }
        return conf;
    }

    private static ImageModerationStatus resolveStatus(
            boolean anyHit,
            boolean anyRejected,
            double maxHitConfidence,
            long clipHitCount,
            boolean localError,
            boolean cloudUnavailable) {

        if (!anyHit) {
            if (localError && !cloudUnavailable) {
                return ImageModerationStatus.FLAGGED;
            }
            return ImageModerationStatus.SAFE;
        }

        // Defensive OR: two CLIP layers agree → reject even if each score is modest
        if (anyRejected || maxHitConfidence >= REJECT_CONFIDENCE || clipHitCount >= 2) {
            return ImageModerationStatus.REJECTED;
        }

        return ImageModerationStatus.FLAGGED;
    }

    /** Primary label for UI — prefer CLIP category, highest confidence among hits. */
    private static Optional<LayerVote> selectPrimaryCategory(
            List<LayerVote> allVotes, List<LayerVote> hits) {

        List<LayerVote> clipHits = hits.stream()
                .filter(v -> isClipLayer(v.layer()))
                .filter(v -> v.category() != null)
                .toList();

        if (!clipHits.isEmpty()) {
            return clipHits.stream()
                    .max(Comparator.comparingDouble(LayerVote::confidence));
        }

        return hits.stream()
                .filter(v -> v.category() != null)
                .max(Comparator.comparingDouble(LayerVote::confidence));
    }

    private static boolean isClipLayer(String layer) {
        return layer != null && layer.toLowerCase().contains("clip");
    }

    private static String buildReason(
            ImageModerationStatus status,
            List<LayerVote> votes,
            List<LayerVote> hits,
            Optional<LayerVote> primary,
            long clipHitCount,
            double ensembleConfidence) {

        if (status == ImageModerationStatus.SAFE) {
            return "No policy violations detected (TriGuard OR: all layers clear).";
        }

        StringBuilder sb = new StringBuilder();
        sb.append(String.format(
                "TriGuard OR: %d/%d layer(s) flagged — ensemble %.0f%%. ",
                hits.size(), votes.size(), ensembleConfidence * 100));

        if (primary.isPresent()) {
            LayerVote v = primary.get();
            sb.append(String.format("Primary: %s (%s, layer max %.0f%%). ",
                    v.category().name(), v.layer(), v.confidence() * 100));
        }

        for (LayerVote v : votes) {
            if (isViolation(v) && v.reason() != null && !v.reason().isBlank()) {
                sb.append(v.reason()).append(' ');
            }
        }

        return sb.toString().trim();
    }

    private static LayerVote toVote(
            String layer,
            Object status,
            double confidence,
            ImageContentCategory category,
            String reason) {

        ImageModerationStatus mapped;
        if (status instanceof HuggingFaceImageService.ImageAnalysisStatus hf) {
            mapped = switch (hf) {
                case REJECTED -> ImageModerationStatus.REJECTED;
                case FLAGGED -> ImageModerationStatus.FLAGGED;
                case ERROR -> ImageModerationStatus.ERROR;
                default -> ImageModerationStatus.SAFE;
            };
        } else if (status instanceof ImageModerationStatus ims) {
            mapped = ims;
        } else {
            mapped = ImageModerationStatus.SAFE;
        }

        return new LayerVote(layer, mapped, confidence, category, reason != null ? reason : "");
    }

    private static ImageContentCategory primaryCategory(List<String> categories) {
        if (categories == null || categories.isEmpty()) return null;
        try {
            String raw = categories.get(0);
            if ("WEAPON".equalsIgnoreCase(raw)) return ImageContentCategory.WEAPONS;
            return ImageContentCategory.valueOf(raw.toUpperCase());
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    private static ImageContentCategory primaryCategoryEnum(List<ImageContentCategory> categories) {
        if (categories == null || categories.isEmpty()) return null;
        return categories.get(0);
    }
}
