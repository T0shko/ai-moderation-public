package com.example.aimoderation.service;

import com.example.aimoderation.model.Sentiment;
import com.example.aimoderation.repository.ModerationTrainingDataRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Service for analyzing sentiment of text content.
 * Uses file-based word filters with priority-based scoring.
 * 
 * KEY PRINCIPLE: Toxic content ALWAYS takes priority.
 * A message with ANY toxic words is NEGATIVE regardless of positive words.
 */
@Service
public class SentimentAnalysisService {

    @Autowired
    private ModerationTrainingDataRepository trainingDataRepository;

    @Autowired
    private WordFilterService wordFilterService;

    public AnalysisResult analyze(String text) {
        if (text == null || text.trim().isEmpty()) {
            return new AnalysisResult(Sentiment.NEUTRAL, 0.5);
        }

        String originalText = text.trim();
        
        // Check for gibberish/spam first
        if (isGibberish(originalText)) {
            return new AnalysisResult(Sentiment.NEGATIVE, 0.9);
        }

        // Normalize text for bypass detection (repeated chars, leet speak, etc.)
        String normalized = normalizeForBypass(originalText.toLowerCase());
        
        // Get filter words from file-based service
        Set<String> toxicWords = wordFilterService.getToxicWords();
        Set<String> negativeIndicators = wordFilterService.getNegativeIndicators();
        Set<String> positiveWords = wordFilterService.getPositiveWords();
        Set<String> sensitiveSubjects = wordFilterService.getSensitiveSubjects();
        Set<String> learnedNegative = getLearnedNegativeTokens();

        // === PHASE 1: Detect toxic content (ABSOLUTE PRIORITY) ===
        int toxicCount = 0;
        double toxicSeverity = 0.0;
        
        for (String word : toxicWords) {
            if (containsWord(normalized, word)) {
                toxicCount++;
                toxicSeverity += 3.0;  // Heavy weight for toxic words
            }
        }
        
        // Check for obfuscated toxic words (f*ck, sh!t, etc.)
        toxicCount += countObfuscatedToxicWords(normalized);
        toxicSeverity += countObfuscatedToxicWords(normalized) * 2.5;
        
        // === CRITICAL: If ANY toxic word is found, it's NEGATIVE. Period. ===
        if (toxicCount > 0) {
            // Calculate confidence based on toxic word count and total words
            String[] words = normalized.split("\\s+");
            double toxicRatio = (double) toxicCount / Math.max(words.length, 1);
            
            // Even ONE toxic word in a 100-word essay = still NEGATIVE
            // More toxic words = higher confidence
            double confidence = Math.min(0.7 + (toxicSeverity * 0.05) + (toxicRatio * 0.2), 0.99);
            
            return new AnalysisResult(Sentiment.NEGATIVE, confidence);
        }
        
        // === PHASE 2: Check for learned negative patterns ===
        for (String token : learnedNegative) {
            if (normalized.contains(token)) {
                return new AnalysisResult(Sentiment.NEGATIVE, 0.85);
            }
        }

        // === PHASE 3: Check negative indicators (less severe than toxic) ===
        double negativeScore = 0;
        int negativeCount = 0;
        
        for (String word : negativeIndicators) {
            if (containsWord(normalized, word)) {
                negativeScore += 1.5;
                negativeCount++;
            }
        }
        
        // Check sensitive subjects in negative context
        for (String subject : sensitiveSubjects) {
            if (normalized.contains(subject)) {
                // Sensitive subjects alone aren't negative, but amplify negativity
                negativeScore += 0.5;
            }
        }

        // === PHASE 4: Check positive words ===
        double positiveScore = 0;
        int positiveCount = 0;
        
        for (String word : positiveWords) {
            if (containsWord(normalized, word)) {
                positiveScore += 1.0;
                positiveCount++;
            }
        }

        // === PHASE 5: Mixed content detection ===
        // If there are negative indicators alongside positive words,
        // the message is suspicious - could be sarcasm or masking
        if (negativeCount > 0 && positiveCount > 0) {
            // Mixed sentiment - lean towards negative if negative indicators present
            if (negativeScore >= positiveScore * 0.5) {
                double confidence = Math.min(0.6 + (negativeScore * 0.1), 0.95);
                return new AnalysisResult(Sentiment.NEGATIVE, confidence);
            }
        }

        // === PHASE 6: Final determination ===
        if (negativeScore > positiveScore && negativeScore > 0.5) {
            double confidence = Math.min(0.5 + (negativeScore * 0.15), 0.95);
            return new AnalysisResult(Sentiment.NEGATIVE, confidence);
        }
        
        if (positiveScore > negativeScore && positiveScore > 1.0) {
            double confidence = Math.min(0.6 + (positiveScore * 0.1), 0.95);
            return new AnalysisResult(Sentiment.POSITIVE, confidence);
        }

        return new AnalysisResult(Sentiment.NEUTRAL, 0.7);
    }

    /**
     * Check if text contains a word (with word boundary awareness)
     */
    private boolean containsWord(String text, String word) {
        // First check simple contains
        if (!text.contains(word)) {
            return false;
        }
        
        // For multi-word phrases, simple contains is enough
        if (word.contains(" ")) {
            return true;
        }
        
        // For single words, check word boundaries to avoid false positives
        // e.g., "class" shouldn't match "ass"
        String pattern = "(?<![a-zA-Z])" + Pattern.quote(word) + "(?![a-zA-Z])";
        return Pattern.compile(pattern).matcher(text).find();
    }

    /**
     * Detect common obfuscation patterns for toxic words
     */
    private int countObfuscatedToxicWords(String text) {
        int count = 0;
        
        // Common obfuscation patterns
        String[][] patterns = {
            // f-word variants
            {"f[\\*\\#\\@\\$\\.\\-\\_]?[uv][\\*\\#\\@\\$\\.\\-\\_]?[c]?[\\*\\#\\@\\$\\.\\-\\_]?[k]", "f-word"},
            {"ph[uv]ck", "f-word"},
            // s-word variants
            {"sh[\\*\\#\\@\\$\\.\\-\\_]?[i1!][\\*\\#\\@\\$\\.\\-\\_]?t", "s-word"},
            {"\\$h[i1!]t", "s-word"},
            // a-word variants
            {"[a@][\\*\\#\\@\\$\\.\\-\\_]?[s\\$][\\*\\#\\@\\$\\.\\-\\_]?[s\\$]", "a-word"},
            // b-word variants
            {"b[\\*\\#\\@\\$\\.\\-\\_]?[i1!][\\*\\#\\@\\$\\.\\-\\_]?t[\\*\\#\\@\\$\\.\\-\\_]?c[\\*\\#\\@\\$\\.\\-\\_]?h", "b-word"},
            // n-word (this should definitely be caught)
            {"n[\\*\\#\\@\\$\\.\\-\\_]?[i1!][\\*\\#\\@\\$\\.\\-\\_]?g+[\\*\\#\\@\\$\\.\\-\\_]?[ae@]?", "n-word"},
        };
        
        for (String[] pattern : patterns) {
            if (Pattern.compile(pattern[0], Pattern.CASE_INSENSITIVE).matcher(text).find()) {
                count++;
            }
        }
        
        return count;
    }

    /**
     * Normalize text to detect bypass attempts
     */
    private String normalizeForBypass(String text) {
        if (text == null) return "";
        
        StringBuilder sb = new StringBuilder();
        
        // Remove repeated characters (e.g., "fuuuuck" -> "fuck")
        if (text.length() > 0) {
            sb.append(text.charAt(0));
            for (int i = 1; i < text.length(); i++) {
                char current = text.charAt(i);
                char previous = text.charAt(i - 1);
                // Allow max 2 repeated chars
                if (i >= 2 && current == previous && text.charAt(i - 2) == previous) {
                    continue;
                }
                sb.append(current);
            }
        }
        
        String result = sb.toString();
        
        // Leet speak conversion
        result = result
            .replace('0', 'o')
            .replace('1', 'i')
            .replace('3', 'e')
            .replace('4', 'a')
            .replace('5', 's')
            .replace('7', 't')
            .replace('@', 'a')
            .replace('$', 's')
            .replace('!', 'i')
            // Cyrillic lookalikes for Bulgarian context
            .replace('а', 'a')
            .replace('е', 'e')
            .replace('о', 'o')
            .replace('с', 'c')
            .replace('р', 'p')
            .replace('х', 'x');
        
        // Remove common separator characters used for obfuscation
        result = result.replaceAll("[\\-\\_\\.\\*]", "");
        
        return result;
    }

    /**
     * Detect gibberish/spam text
     */
    private boolean isGibberish(String text) {
        // Check for long consonant sequences (nonsense)
        boolean hasLongConsonants = Pattern
            .compile("[^aeiouаеиоуъяю\\s]{7,}", Pattern.CASE_INSENSITIVE)
            .matcher(text)
            .find();
        
        // Check for very low character diversity in long text
        long uniqueChars = text.chars().distinct().count();
        boolean lowDiversity = text.length() > 20 && 
            (double) uniqueChars / text.length() < 0.15;
        
        // Check for repeated word spam
        String[] words = text.split("\\s+");
        if (words.length > 5) {
            Set<String> uniqueWords = Set.of(words);
            double wordDiversity = (double) uniqueWords.size() / words.length;
            if (wordDiversity < 0.2) {
                return true; // Too many repeated words
            }
        }
        
        return hasLongConsonants || lowDiversity;
    }

    /**
     * Get tokens from learned negative training data
     */
    private Set<String> getLearnedNegativeTokens() {
        return trainingDataRepository.findAll().stream()
            .filter(data -> "NEGATIVE".equals(data.getLabel()))
            .map(data -> normalizeForBypass(data.getContent().toLowerCase().trim()))
            .filter(content -> !content.isEmpty())
            .collect(Collectors.toSet());
    }

    public static class AnalysisResult {
        private final Sentiment sentiment;
        private final Double confidence;

        public AnalysisResult(Sentiment sentiment, Double confidence) {
            this.sentiment = sentiment;
            this.confidence = confidence;
        }

        public Sentiment getSentiment() {
            return sentiment;
        }

        public Double getConfidence() {
            return confidence;
        }
    }
}
