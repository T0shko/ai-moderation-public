package com.example.aimoderation.service;

import com.example.aimoderation.model.Sentiment;
import com.example.aimoderation.util.TextNormalizer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Enterprise tie-break: no weak NEUTRAL@50% for end users — every comment resolves to POSITIVE or NEGATIVE.
 */
@Service
public class TextVerdictResolverService {

    private static final double AMBIGUOUS_BAND_LOW = 0.45;
    private static final double AMBIGUOUS_BAND_HIGH = 0.55;

    @Autowired
    private ContextualTextModeration contextualTextModeration;

    @Autowired
    private TextContextAiService textContextAiService;

    @Value("${moderation.text.default-ambiguous:approve}")
    private String defaultAmbiguous;

    /**
     * Final pass: ensure diploma/product always gets a clear positive or negative verdict.
     */
    public SentimentAnalysisService.AnalysisResult finalizeVerdict(
            String originalText,
            SentimentAnalysisService.AnalysisResult preliminary) {

        Sentiment sentiment = preliminary.getSentiment();
        double confidence = preliminary.getConfidence() != null ? preliminary.getConfidence() : 0.5;
        String reason = preliminary.getReason();

        if (preliminary.isGibberish()) {
            return withSentiment(preliminary, Sentiment.NEGATIVE, Math.max(confidence, 0.88),
                    reason != null ? reason : "Spam or gibberish detected.");
        }

        if (sentiment == Sentiment.NEGATIVE && confidence >= 0.55) {
            return withSentiment(preliminary, Sentiment.NEGATIVE, confidence, reason);
        }

        if (sentiment == Sentiment.POSITIVE && confidence >= 0.55) {
            return withSentiment(preliminary, Sentiment.POSITIVE, confidence, reason);
        }

        String normalized = TextNormalizer.normalize(originalText);

        ContextualTextModeration.ContextVerdict ctx = contextualTextModeration.analyze(normalized);
        if (ctx == ContextualTextModeration.ContextVerdict.MALICIOUS) {
            return withSentiment(preliminary, Sentiment.NEGATIVE, 0.78,
                    "Contextual threat or insult detected.");
        }
        if (ctx == ContextualTextModeration.ContextVerdict.BENIGN) {
            return withSentiment(preliminary, Sentiment.POSITIVE, 0.8,
                    "Benign phrase recognized in context.");
        }

        if (textContextAiService.isAvailable()) {
            TextContextAiService.AiVerdict ai = textContextAiService.adjudicate(originalText);
            if (ai == TextContextAiService.AiVerdict.SAFE) {
                return withSentiment(preliminary, Sentiment.POSITIVE, 0.72,
                        "AI verdict: acceptable content.");
            }
            if (ai == TextContextAiService.AiVerdict.TOXIC) {
                return withSentiment(preliminary, Sentiment.NEGATIVE, 0.78,
                        "AI verdict: policy violation.");
            }
            if (ai == TextContextAiService.AiVerdict.REVIEW) {
                return resolveDefaultAmbiguous(preliminary, normalized,
                        "AI could not decide with certainty; applied enterprise default.");
            }
        }

        if (isAmbiguousBand(confidence) || sentiment == Sentiment.NEUTRAL) {
            return resolveDefaultAmbiguous(preliminary, normalized,
                    "Phase 6: enterprise default applied.");
        }

        if (sentiment == Sentiment.NEGATIVE) {
            return withSentiment(preliminary, Sentiment.NEGATIVE, Math.max(confidence, 0.62), reason);
        }

        return withSentiment(preliminary, Sentiment.POSITIVE, Math.max(confidence, 0.62), reason);
    }

    private SentimentAnalysisService.AnalysisResult resolveDefaultAmbiguous(
            SentimentAnalysisService.AnalysisResult preliminary,
            String normalized,
            String prefix) {

        boolean strict = "reject".equalsIgnoreCase(defaultAmbiguous);
        if (strict) {
            return withSentiment(preliminary, Sentiment.NEGATIVE, 0.55,
                    prefix + " Default: rejected (strict mode).");
        }
        if (normalized.length() < 3) {
            return withSentiment(preliminary, Sentiment.NEGATIVE, 0.6,
                    prefix + " Empty or too short.");
        }
        return withSentiment(preliminary, Sentiment.POSITIVE, 0.62,
                prefix + " Default: approved (no violation signals).");
    }

    private boolean isAmbiguousBand(double confidence) {
        return confidence >= AMBIGUOUS_BAND_LOW && confidence <= AMBIGUOUS_BAND_HIGH;
    }

    private SentimentAnalysisService.AnalysisResult withSentiment(
            SentimentAnalysisService.AnalysisResult source,
            Sentiment sentiment,
            double confidence,
            String reason) {
        return new SentimentAnalysisService.AnalysisResult(
                sentiment,
                confidence,
                reason,
                source.isSensitiveOnly() && sentiment == Sentiment.NEGATIVE,
                source.isGibberish());
    }
}
