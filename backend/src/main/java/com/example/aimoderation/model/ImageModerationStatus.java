package com.example.aimoderation.model;

/**
 * Status of an image moderation check.
 */
public enum ImageModerationStatus {
    PENDING,      // Waiting for moderation
    SAFE,         // Image passed moderation
    FLAGGED,      // Image flagged for manual review
    REJECTED,     // Image rejected as inappropriate
    ERROR         // Error during moderation process
}
