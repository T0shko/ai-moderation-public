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
            "[^aeiouаеиоуъяю\\s]{7,}", Pattern.CASE_INSENSITIVE);
    private static final Pattern OBFUSCATION_PATTERNS = Pattern.compile(
            "f[\\*#@$.\\-_]?[uv][\\*#@$.\\-_]?[c]?[\\*#@$.\\-_]?[k]|"
                    + "ph[uv]ck|sh[\\*#@$.\\-_]?[i1!][\\*#@$.\\-_]?t|\\$h[i1!]t|"
                    + "[a@][\\*#@$.\\-_]?[s$][\\*#@$.\\-_]?[s$]|"
                    + "b[\\*#@$.\\-_]?[i1!][\\*#@$.\\-_]?t[\\*#@$.\\-_]?c[\\*#@$.\\-_]?h|"
                    + "n[\\*#@$.\\-_]?[i1!][\\*#@$.\\-_]?g+[\\*#@$.\\-_]?[ae@]?",
            Pattern.CASE_INSENSITIVE);

    private final AtomicReference<Set<String>> learnedNegativeCache = new AtomicReference<>(Set.of());
    private volatile long learnedCacheLoadedAt = 0;
    private static final long LEARNED_CACHE_TTL_MS = 60_000;

    @Autowired
    private ModerationTrainingDataRepository trainingDataRepository;

    @Autowired
    private WordFilterService wordFilterService;

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

        Set<String> toxicWords = wordFilterService.getToxicWords();
        Set<String> negativeIndicators = wordFilterService.getNegativeIndicators();
        Set<String> positiveWords = wordFilterService.getPositiveWords();
        Set<String> sensitiveSubjects = wordFilterService.getSensitiveSubjects();
        Set<String> learnedNegative = getLearnedNegativeTokens();

        int toxicCount = 0;
        double toxicSeverity = 0.0;

        for (String word : toxicWords) {
            if (containsWord(normalized, compact, word)) {
                toxicCount++;
                toxicSeverity += 3.0;
            }
        }

        int obfuscated = countObfuscatedToxicWords(normalized);
        if (obfuscated > 0) {
            toxicCount += obfuscated;
            toxicSeverity += obfuscated * 2.5;
        }

        if (toxicCount > 0) {
            String[] words = normalized.split("\\s+");
            double toxicRatio = (double) toxicCount / Math.max(words.length, 1);
            double confidence = Math.min(0.7 + (toxicSeverity * 0.05) + (toxicRatio * 0.2), 0.99);
            return new AnalysisResult(Sentiment.NEGATIVE, confidence,
                    "Toxic language detected (" + toxicCount + " match(es)).", false, false);
        }

        for (String token : learnedNegative) {
            if (containsWord(normalized, compact, token)) {
                return new AnalysisResult(Sentiment.NEGATIVE, 0.85,
                        "Matches a pattern from moderator training data.", false, false);
            }
        }

        double negativeScore = 0;
        int negativeCount = 0;
        List<String> matchedNegative = new ArrayList<>();

        for (String word : negativeIndicators) {
            if (containsWord(normalized, compact, word)) {
                negativeScore += 1.5;
                negativeCount++;
                matchedNegative.add(word);
            }
        }

        boolean sensitiveOnly = false;
        List<String> matchedSensitive = new ArrayList<>();
        for (String subject : sensitiveSubjects) {
            if (containsWord(normalized, compact, subject)) {
                negativeScore += 1.0;
                matchedSensitive.add(subject);
            }
        }
        if (!matchedSensitive.isEmpty() && matchedNegative.isEmpty() && toxicCount == 0) {
            sensitiveOnly = true;
        }

        double positiveScore = 0;
        int positiveCount = 0;
        for (String word : positiveWords) {
            if (containsWord(normalized, compact, word)) {
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

        return new AnalysisResult(Sentiment.NEUTRAL, 0.5,
                "No strong moderation signals; review recommended if unsure.", false, false);
    }

    boolean containsWord(String normalized, String compact, String word) {
        if (word == null || word.isBlank()) return false;
        String w = word.trim().toLowerCase();
        if (w.contains(" ")) {
            return normalized.contains(w) || compact.contains(w.replace(" ", ""));
        }
        if (normalized.contains(w) || compact.contains(w)) {
            String pattern = "(?<![a-zA-Z])" + Pattern.quote(w) + "(?![a-zA-Z])";
            return Pattern.compile(pattern).matcher(normalized).find()
                    || compact.contains(w);
        }
        return false;
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
                .filter(token -> token.length() >= 4 && token.length() <= 64)
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
