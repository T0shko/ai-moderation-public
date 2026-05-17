package com.example.aimoderation.service;

import com.example.aimoderation.util.TextNormalizer;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.regex.Pattern;

@Service
public class WordFilterService {

    private static final Logger logger = LoggerFactory.getLogger(WordFilterService.class);

    @Value("${filter.toxic-words.path:filters/toxic-words.txt}")
    private String toxicWordsPath;

    @Value("${filter.negative-indicators.path:filters/negative-indicators.txt}")
    private String negativeIndicatorsPath;

    @Value("${filter.positive-words.path:filters/positive-words.txt}")
    private String positiveWordsPath;

    @Value("${filter.sensitive-subjects.path:filters/sensitive-subjects.txt}")
    private String sensitiveSubjectsPath;

    private volatile Set<String> toxicWords = Set.of();
    private volatile Set<String> negativeIndicators = Set.of();
    private volatile Set<String> positiveWords = Set.of();
    private volatile Set<String> sensitiveSubjects = Set.of();

    @PostConstruct
    public void init() {
        reloadAllFilters();
    }

    public void reloadAllFilters() {
        logger.info("Reloading all word filters...");
        toxicWords = loadFilterFile(toxicWordsPath, "toxic words");
        negativeIndicators = loadFilterFile(negativeIndicatorsPath, "negative indicators");
        positiveWords = loadFilterFile(positiveWordsPath, "positive words");
        sensitiveSubjects = loadFilterFile(sensitiveSubjectsPath, "sensitive subjects");
        logger.info("Word filters reloaded: {} toxic, {} negative, {} positive, {} sensitive",
                toxicWords.size(), negativeIndicators.size(), positiveWords.size(), sensitiveSubjects.size());
    }

    private Set<String> loadFilterFile(String path, String filterName) {
        Set<String> loadedWords = new HashSet<>();
        try {
            ClassPathResource resource = new ClassPathResource(path);
            if (!resource.exists()) {
                logger.warn("Filter file not found: {}. {} filter will be empty.", path, filterName);
                return Set.of();
            }
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(resource.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    String trimmed = line.trim().toLowerCase();
                    if (!trimmed.isEmpty() && !trimmed.startsWith("#")) {
                        loadedWords.add(trimmed);
                    }
                }
            }
            return Collections.unmodifiableSet(loadedWords);
        } catch (IOException e) {
            logger.error("Error loading {} filter from {}: {}", filterName, path, e.getMessage());
            return Set.of();
        }
    }

    public Set<String> getToxicWords() {
        return toxicWords;
    }

    public Set<String> getNegativeIndicators() {
        return negativeIndicators;
    }

    public Set<String> getPositiveWords() {
        return positiveWords;
    }

    public Set<String> getSensitiveSubjects() {
        return sensitiveSubjects;
    }

    public boolean containsToxicWord(String text) {
        return matchesAny(text, toxicWords);
    }

    public boolean containsNegativeIndicator(String text) {
        return matchesAny(text, negativeIndicators);
    }

    public boolean containsPositiveWord(String text) {
        return matchesAny(text, positiveWords);
    }

    public int countMatches(String text, Set<String> filterWords) {
        if (text == null || filterWords == null) return 0;
        String normalized = TextNormalizer.normalize(text);
        String compact = TextNormalizer.compact(normalized);
        return (int) filterWords.stream()
                .filter(word -> wordMatches(normalized, compact, word))
                .count();
    }

    private boolean matchesAny(String text, Set<String> filterWords) {
        if (text == null) return false;
        String normalized = TextNormalizer.normalize(text);
        String compact = TextNormalizer.compact(normalized);
        return filterWords.stream().anyMatch(word -> wordMatches(normalized, compact, word));
    }

    private boolean wordMatches(String normalized, String compact, String word) {
        if (word.contains(" ")) {
            return normalized.contains(word) || compact.contains(word.replace(" ", ""));
        }
        if (normalized.contains(word) || compact.contains(word)) {
            String pattern = "(?<![a-zA-Z])" + Pattern.quote(word) + "(?![a-zA-Z])";
            return Pattern.compile(pattern).matcher(normalized).find() || compact.contains(word);
        }
        return false;
    }
}
