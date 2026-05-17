package com.example.aimoderation.service;

import com.example.aimoderation.config.AppModerationProperties;
import com.example.aimoderation.model.AiSettings;
import com.example.aimoderation.model.CommentStatus;
import com.example.aimoderation.model.Sentiment;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

/**
 * Single source of truth for comment moderation status decisions.
 */
@Service
public class ModerationDecisionService {

    @Autowired
    private AppModerationProperties appProperties;

    public ModerationDecision decide(SentimentAnalysisService.AnalysisResult analysis, AiSettings settings) {
        double threshold = resolveThreshold(settings);
        double autoRejectThreshold = appProperties.getModeration().getAutoRejectThreshold();
        boolean autoRejectEnabled = appProperties.getModeration().isAutoRejectHighConfidence();

        Sentiment sentiment = analysis.getSentiment();
        double confidence = analysis.getConfidence() != null ? analysis.getConfidence() : 0.5;
        boolean blocked = sentiment == Sentiment.NEGATIVE
                || analysis.isSensitiveOnly()
                || analysis.isGibberish();

        CommentStatus status;
        if (blocked && autoRejectEnabled && confidence >= autoRejectThreshold) {
            status = CommentStatus.REJECTED;
        } else if (blocked || confidence < threshold) {
            status = CommentStatus.PENDING;
        } else if (sentiment == Sentiment.POSITIVE
                && appProperties.getModeration().isAutoApprovePositive()
                && confidence >= threshold) {
            status = CommentStatus.APPROVED;
        } else {
            // Safe-by-default: NEUTRAL or weak signals require review
            status = CommentStatus.PENDING;
        }

        boolean wouldBeAutoApproved = status == CommentStatus.APPROVED;
        return new ModerationDecision(status, wouldBeAutoApproved, analysis.getReason(), sentiment, confidence);
    }

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
