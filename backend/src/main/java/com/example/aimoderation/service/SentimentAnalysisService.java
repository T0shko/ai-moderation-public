package com.example.aimoderation.service;

import com.example.aimoderation.model.Sentiment;
import com.example.aimoderation.repository.ModerationTrainingDataRepository;
import com.example.aimoderation.util.TextNormalizer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@Service
public class SentimentAnalysisService {

    private static final Pattern LONG_CONSONANTS = Pattern.compile(
            "[^aeiouаеиоуъяю\\s]{7,}", Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);
    private static final Pattern OBFUSCATION_PATTERNS = Pattern.compile(
            "f[\\*#@$.\\-_]?[uv][\\*#@$.\\-_]?[c]?[\\*#@$.\\-_]?[k]|"
                    + "ph[uv]ck|sh[\\*#@$.\\-_]?[i1!][\\*#@$.\\-_]?t|\\$h[i1!]t|"
                    + "[a@][\\*#@$.\\-_]?[s$][\\*#@$.\\-_]?[s$]|"
                    + "b[\\*#@$.\\-_]?[i1!][\\*#@$.\\-_]?t[\\*#@$.\\-_]?c[\\*#@$.\\-_]?h|"
                    + "n[\\*#@$.\\-_]?[i1!][\\*#@$.\\-_]?g+[\\*#@$.\\-_]?[ae@]?|"
                    + "k[\\*#@$.\\-_]?[y1][\\*#@$.\\-_]?[s$5]|"
                    + "k[\\*#@$.\\-_]?[m][\\*#@$.\\-_]?[s$5]",
            Pattern.CASE_INSENSITIVE);

    private final AtomicReference<Set<String>> learnedNegativeCache = new AtomicReference<>(Set.of());
    private volatile long learnedCacheLoadedAt = 0;
    private static final long LEARNED_CACHE_TTL_MS = 60_000;

    @Autowired
    private ModerationTrainingDataRepository trainingDataRepository;

    @Autowired
    private WordFilterService wordFilterService;

    @Autowired
    private ContextualTextModeration contextualTextModeration;

    @Autowired
    private TextContextAiService textContextAiService;

    @Autowired
    private TextVerdictResolverService textVerdictResolverService;

    public AnalysisResult analyze(String text) {
        if (text == null || text.trim().isEmpty()) {
            return new AnalysisResult(Sentiment.NEUTRAL, 0.5, "Empty content.", false, false);
        }

        String originalText = text.trim();
        String normalized = TextNormalizer.normalize(originalText);
        String compact = TextNormalizer.compact(normalized);

        if (isGibberish(originalText)) {
            return new AnalysisResult(Sentiment.NEGATIVE, 0.9,
                    "Gibberish or spam-like text detected.", false, true);
        }

        // Pragmatic context (thesis §1.3) before lexical phases
        ContextualTextModeration.ContextVerdict contextVerdict =
                contextualTextModeration.analyze(normalized);
        if (contextVerdict == ContextualTextModeration.ContextVerdict.MALICIOUS) {
            return new AnalysisResult(Sentiment.NEGATIVE, 0.92,
                    "Phase context: insulting phrase.", false, false);
        }
        if (contextVerdict == ContextualTextModeration.ContextVerdict.BENIGN) {
            return new AnalysisResult(Sentiment.POSITIVE, 0.82,
                    "Phase context: benign phrasing (e.g. compliment or colloquial).", false, false);
        }

        Set<String> toxicWords = wordFilterService.getToxicWords();
        Set<String> slangToxic = wordFilterService.getSlangToxic();
        Set<String> phrasesToxic = wordFilterService.getPhrasesToxic();
        Set<String> negativeIndicators = wordFilterService.getNegativeIndicators();
        Set<String> positiveWords = wordFilterService.getPositiveWords();
        Set<String> sensitiveSubjects = wordFilterService.getSensitiveSubjects();
        Set<String> learnedNegative = getLearnedNegativeTokens();

        String primaryMatch = null;
        int toxicCount = 0;
        double toxicSeverity = 0.0;

        for (String phrase : phrasesToxic) {
            if (wordFilterService.wordMatches(normalized, compact, phrase)
                    && !contextualTextModeration.shouldSuppressTokenMatch(normalized, phrase)) {
                toxicCount++;
                toxicSeverity += 4.0;
                if (primaryMatch == null) primaryMatch = phrase;
            }
        }

        for (String slang : slangToxic) {
            if (wordFilterService.wordMatches(normalized, compact, slang)
                    && !contextualTextModeration.shouldSuppressTokenMatch(normalized, slang)) {
                toxicCount++;
                toxicSeverity += 3.5;
                if (primaryMatch == null) primaryMatch = slang;
            }
        }

        for (String word : toxicWords) {
            if (wordFilterService.wordMatches(normalized, compact, word)
                    && !contextualTextModeration.shouldSuppressTokenMatch(normalized, word)) {
                toxicCount++;
                toxicSeverity += 3.0;
                if (primaryMatch == null) primaryMatch = word;
            }
        }

        int obfuscated = countObfuscatedToxicWords(normalized);
        if (obfuscated > 0) {
            toxicCount += obfuscated;
            toxicSeverity += obfuscated * 2.5;
            if (primaryMatch == null) primaryMatch = "obfuscated toxic pattern";
        }

        if (toxicCount > 0) {
            if (textContextAiService.isAvailable()) {
                TextContextAiService.AiVerdict aiVerdict = textContextAiService.adjudicate(originalText);
                if (aiVerdict == TextContextAiService.AiVerdict.SAFE) {
                    return new AnalysisResult(Sentiment.POSITIVE, 0.78,
                            "AI context check: acceptable phrasing despite keyword overlap.", false, false);
                }
            }
            String[] words = normalized.split("\\s+");
            double toxicRatio = (double) toxicCount / Math.max(words.length, 1);
            double confidence = Math.min(0.7 + (toxicSeverity * 0.05) + (toxicRatio * 0.2), 0.99);
            String reason = primaryMatch != null
                    ? "Toxic language detected — primary match: \"" + primaryMatch + "\"."
                    : "Toxic language detected.";
            return new AnalysisResult(Sentiment.NEGATIVE, confidence, reason, false, false);
        }

        for (String token : learnedNegative) {
            if (wordFilterService.wordMatches(normalized, compact, token)
                    && !contextualTextModeration.shouldSuppressTokenMatch(normalized, token)) {
                return new AnalysisResult(Sentiment.NEGATIVE, 0.85,
                        "Matches a pattern from moderator training data.", false, false);
            }
        }

        double negativeScore = 0;
        int negativeCount = 0;
        List<String> matchedNegative = new ArrayList<>();

        for (String word : negativeIndicators) {
            if (wordFilterService.wordMatches(normalized, compact, word)) {
                negativeScore += 1.5;
                negativeCount++;
                matchedNegative.add(word);
            }
        }

        boolean sensitiveOnly = false;
        List<String> matchedSensitive = new ArrayList<>();
        for (String subject : sensitiveSubjects) {
            if (wordFilterService.wordMatches(normalized, compact, subject)
                    && !contextualTextModeration.shouldSuppressTokenMatch(normalized, subject)) {
                negativeScore += 1.0;
                matchedSensitive.add(subject);
            }
        }
        if (!matchedSensitive.isEmpty() && matchedNegative.isEmpty() && toxicCount == 0
                && !contextualTextModeration.isBenignFamilyContext(normalized)) {
            sensitiveOnly = true;
        }

        double positiveScore = 0;
        int positiveCount = 0;
        for (String word : positiveWords) {
            if (wordFilterService.wordMatches(normalized, compact, word)) {
                positiveScore += 1.0;
                positiveCount++;
            }
        }

        if (negativeCount > 0 && positiveCount > 0 && negativeScore >= positiveScore * 0.5) {
            double confidence = Math.min(0.6 + (negativeScore * 0.1), 0.95);
            return new AnalysisResult(Sentiment.NEGATIVE, confidence,
                    "Mixed content with negative indicators.", false, false);
        }

        if (sensitiveOnly) {
            TextContextAiService.AiVerdict aiVerdict = textContextAiService.adjudicate(originalText);
            if (aiVerdict == TextContextAiService.AiVerdict.SAFE) {
                return new AnalysisResult(Sentiment.POSITIVE, 0.8,
                        "AI context check: acceptable phrasing.", false, false);
            }
            if (aiVerdict == TextContextAiService.AiVerdict.TOXIC) {
                return new AnalysisResult(Sentiment.NEGATIVE, 0.88,
                        "AI context check: policy violation.", false, false);
            }
            return new AnalysisResult(Sentiment.NEGATIVE, 0.75,
                    "Sensitive subject detected: " + String.join(", ", matchedSensitive) + ".",
                    true, false);
        }

        if (negativeScore > positiveScore && negativeScore > 0.5) {
            double confidence = Math.min(0.5 + (negativeScore * 0.15), 0.95);
            return new AnalysisResult(Sentiment.NEGATIVE, confidence,
                    "Negative language indicators detected.", false, false);
        }

        if (positiveScore > negativeScore && positiveScore >= 1.0) {
            double confidence = Math.min(0.6 + (positiveScore * 0.1), 0.95);
            return new AnalysisResult(Sentiment.POSITIVE, confidence,
                    "Positive sentiment detected.", false, false);
        }

        AnalysisResult neutral = new AnalysisResult(Sentiment.NEUTRAL, 0.5,
                "No strong moderation signals.", false, false);
        return textVerdictResolverService.finalizeVerdict(originalText, neutral);
    }

    private int countObfuscatedToxicWords(String text) {
        return OBFUSCATION_PATTERNS.matcher(text).find() ? 1 : 0;
    }

    private boolean isGibberish(String text) {
        if (text.length() < 12) {
            return false;
        }
        String[] words = text.split("\\s+");
        if (words.length < 2) {
            return false;
        }

        boolean hasLongConsonants = LONG_CONSONANTS.matcher(text).find();
        long uniqueChars = text.chars().distinct().count();
        boolean lowDiversity = text.length() > 20 && (double) uniqueChars / text.length() < 0.15;

        if (words.length > 5) {
            Set<String> uniqueWords = Set.of(words);
            double wordDiversity = (double) uniqueWords.size() / words.length;
            if (wordDiversity < 0.2) {
                return true;
            }
        }

        return hasLongConsonants || lowDiversity;
    }

    private Set<String> getLearnedNegativeTokens() {
        long now = System.currentTimeMillis();
        if (now - learnedCacheLoadedAt < LEARNED_CACHE_TTL_MS) {
            return learnedNegativeCache.get();
        }
        Set<String> tokens = trainingDataRepository.findAll().stream()
                .filter(data -> "NEGATIVE".equals(data.getLabel()))
                .map(data -> data.getContent())
                .filter(content -> content != null && !content.isBlank())
                .flatMap(content -> java.util.Arrays.stream(content.split("[|,]")))
                .map(String::trim)
                .map(String::toLowerCase)
                .filter(token -> token.length() >= 2 && token.length() <= 96)
                .collect(Collectors.toUnmodifiableSet());
        learnedNegativeCache.set(tokens);
        learnedCacheLoadedAt = now;
        return tokens;
    }

    public void invalidateLearnedCache() {
        learnedCacheLoadedAt = 0;
    }

    public static class AnalysisResult {
        private final Sentiment sentiment;
        private final Double confidence;
        private final String reason;
        private final boolean sensitiveOnly;
        private final boolean gibberish;

        public AnalysisResult(Sentiment sentiment, Double confidence, String reason,
                              boolean sensitiveOnly, boolean gibberish) {
            this.sentiment = sentiment;
            this.confidence = confidence;
            this.reason = reason;
            this.sensitiveOnly = sensitiveOnly;
            this.gibberish = gibberish;
        }

        public Sentiment getSentiment() { return sentiment; }
        public Double getConfidence() { return confidence; }
        public String getReason() { return reason; }
        public boolean isSensitiveOnly() { return sensitiveOnly; }
        public boolean isGibberish() { return gibberish; }
    }
}
