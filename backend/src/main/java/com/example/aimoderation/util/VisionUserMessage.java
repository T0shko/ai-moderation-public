package com.example.aimoderation.util;

import com.example.aimoderation.model.ImageModerationStatus;

import java.util.List;

/** Short copy for end users — technical details stay in logs / debug fields. */
public final class VisionUserMessage {

    private VisionUserMessage() {}

    public static String forStatus(ImageModerationStatus status, List<String> categories) {
        if (status == null) {
            return "We could not check this photo.";
        }
        return switch (status) {
            case SAFE -> "Your photo looks fine — you can post it.";
            case REJECTED, FLAGGED -> blockedMessage(categories);
            case ERROR -> "We could not check this photo. Try again.";
            case PENDING -> "This photo needs a quick review.";
        };
    }

    private static String blockedMessage(List<String> categories) {
        if (categories == null || categories.isEmpty()) {
            return "This photo is not allowed on our community wall.";
        }
        String friendly = friendlyCategory(categories.get(0));
        return "This photo is not allowed (" + friendly + ").";
    }

    private static String friendlyCategory(String raw) {
        if (raw == null || raw.isBlank()) {
            return "restricted content";
        }
        return switch (raw.toUpperCase()) {
            case "ADULT" -> "adult content";
            case "WEAPONS" -> "weapons";
            case "VIOLENCE" -> "violence";
            case "HATE_SYMBOLS" -> "hate symbols";
            case "DRUGS" -> "drugs";
            case "SPAM" -> "spam";
            case "SELF_HARM" -> "self-harm";
            case "OTHER" -> "restricted content";
            default -> raw.toLowerCase().replace('_', ' ');
        };
    }
}
