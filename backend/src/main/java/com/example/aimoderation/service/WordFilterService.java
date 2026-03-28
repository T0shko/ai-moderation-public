package com.example.aimoderation.service;

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
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service for loading and managing word filters from external files.
 * Filters are loaded from the classpath at startup and can be reloaded at runtime.
 */
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
    
    private final Set<String> toxicWords = ConcurrentHashMap.newKeySet();
    private final Set<String> negativeIndicators = ConcurrentHashMap.newKeySet();
    private final Set<String> positiveWords = ConcurrentHashMap.newKeySet();
    private final Set<String> sensitiveSubjects = ConcurrentHashMap.newKeySet();
    
    @PostConstruct
    public void init() {
        reloadAllFilters();
    }
    
    /**
     * Reloads all filter files from the classpath.
     * This can be called at runtime to refresh filters without restarting the application.
     */
    public void reloadAllFilters() {
        logger.info("Reloading all word filters...");
        
        loadFilterFile(toxicWordsPath, toxicWords, "toxic words");
        loadFilterFile(negativeIndicatorsPath, negativeIndicators, "negative indicators");
        loadFilterFile(positiveWordsPath, positiveWords, "positive words");
        loadFilterFile(sensitiveSubjectsPath, sensitiveSubjects, "sensitive subjects");
        
        logger.info("Word filters reloaded successfully. Loaded: {} toxic, {} negative, {} positive, {} sensitive",
                toxicWords.size(), negativeIndicators.size(), positiveWords.size(), sensitiveSubjects.size());
    }
    
    private void loadFilterFile(String path, Set<String> targetSet, String filterName) {
        Set<String> loadedWords = new HashSet<>();
        
        try {
            ClassPathResource resource = new ClassPathResource(path);
            
            if (!resource.exists()) {
                logger.warn("Filter file not found: {}. {} filter will be empty.", path, filterName);
                return;
            }
            
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(resource.getInputStream(), StandardCharsets.UTF_8))) {
                
                String line;
                while ((line = reader.readLine()) != null) {
                    String trimmed = line.trim().toLowerCase();
                    
                    // Skip empty lines and comments
                    if (!trimmed.isEmpty() && !trimmed.startsWith("#")) {
                        loadedWords.add(trimmed);
                    }
                }
            }
            
            // Atomic update of the filter set
            targetSet.clear();
            targetSet.addAll(loadedWords);
            
            logger.debug("Loaded {} {} from {}", loadedWords.size(), filterName, path);
            
        } catch (IOException e) {
            logger.error("Error loading {} filter from {}: {}", filterName, path, e.getMessage());
        }
    }
    
    public Set<String> getToxicWords() {
        return new HashSet<>(toxicWords);
    }
    
    public Set<String> getNegativeIndicators() {
        return new HashSet<>(negativeIndicators);
    }
    
    public Set<String> getPositiveWords() {
        return new HashSet<>(positiveWords);
    }
    
    public Set<String> getSensitiveSubjects() {
        return new HashSet<>(sensitiveSubjects);
    }
    
    /**
     * Check if text contains any toxic words.
     */
    public boolean containsToxicWord(String text) {
        if (text == null) return false;
        String normalized = text.toLowerCase();
        return toxicWords.stream().anyMatch(normalized::contains);
    }
    
    /**
     * Check if text contains any negative indicators.
     */
    public boolean containsNegativeIndicator(String text) {
        if (text == null) return false;
        String normalized = text.toLowerCase();
        return negativeIndicators.stream().anyMatch(normalized::contains);
    }
    
    /**
     * Check if text contains any positive words.
     */
    public boolean containsPositiveWord(String text) {
        if (text == null) return false;
        String normalized = text.toLowerCase();
        return positiveWords.stream().anyMatch(normalized::contains);
    }
    
    /**
     * Count occurrences of words from a filter set in the text.
     */
    public int countMatches(String text, Set<String> filterWords) {
        if (text == null || filterWords == null) return 0;
        String normalized = text.toLowerCase();
        return (int) filterWords.stream()
                .filter(normalized::contains)
                .count();
    }
}
