package com.example.aimoderation.service;

import com.example.aimoderation.config.AppModerationProperties;
import com.example.aimoderation.model.AiSettings;
import com.example.aimoderation.model.CommentStatus;
import com.example.aimoderation.model.Sentiment;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

/**
 * Decisive product logic: comments are APPROVED or REJECTED — not left in PENDING
 * unless operators explicitly need a queue (disabled for end-user flow).
 */
@Service
public class ModerationDecisionService {

    @Autowired
    private AppModerationProperties appProperties;

    public ModerationDecision decide(SentimentAnalysisService.AnalysisResult analysis, AiSettings settings) {
        double autoRejectThreshold = appProperties.getModeration().getAutoRejectThreshold();
        boolean autoRejectEnabled = appProperties.getModeration().isAutoRejectHighConfidence();

        Sentiment sentiment = analysis.getSentiment();
        double confidence = analysis.getConfidence() != null ? analysis.getConfidence() : 0.5;

        CommentStatus status;
        String reason = analysis.getReason();

        if (analysis.isGibberish() || sentiment == Sentiment.NEGATIVE) {
            status = CommentStatus.REJECTED;
            if (autoRejectEnabled && confidence < autoRejectThreshold) {
                reason = (reason != null ? reason : "") + " (auto-reject policy)";
            }
        } else if (sentiment == Sentiment.POSITIVE) {
            status = CommentStatus.APPROVED;
        } else {
            status = CommentStatus.APPROVED;
            reason = (reason != null ? reason : "") + " Resolved as acceptable.";
        }

        return new ModerationDecision(
                status,
                status == CommentStatus.APPROVED,
                reason,
                sentiment,
                confidence);
    }

    @SuppressWarnings("unused")
    private double resolveThreshold(AiSettings settings) {
        if (settings != null && settings.getThreshold() != null) {
            return settings.getThreshold();
        }
        return appProperties.getModeration().getThreshold();
    }

    public record ModerationDecision(
            CommentStatus status,
            boolean wouldBeAutoApproved,
            String reason,
            Sentiment sentiment,
            double confidence) {}
}
