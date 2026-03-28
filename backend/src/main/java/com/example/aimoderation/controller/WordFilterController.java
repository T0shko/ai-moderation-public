package com.example.aimoderation.controller;

import com.example.aimoderation.service.WordFilterService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/**
 * REST controller for managing word filters.
 */
@RestController
@RequestMapping("/api/filters")
@CrossOrigin(origins = "*")
public class WordFilterController {

    @Autowired
    private WordFilterService wordFilterService;

    /**
     * Get all filter categories and their word counts.
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> getFilterStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("toxicWords", wordFilterService.getToxicWords().size());
        stats.put("negativeIndicators", wordFilterService.getNegativeIndicators().size());
        stats.put("positiveWords", wordFilterService.getPositiveWords().size());
        stats.put("sensitiveSubjects", wordFilterService.getSensitiveSubjects().size());
        return ResponseEntity.ok(stats);
    }

    /**
     * Get toxic words list.
     */
    @GetMapping("/toxic")
    public ResponseEntity<Set<String>> getToxicWords() {
        return ResponseEntity.ok(wordFilterService.getToxicWords());
    }

    /**
     * Get negative indicators list.
     */
    @GetMapping("/negative")
    public ResponseEntity<Set<String>> getNegativeIndicators() {
        return ResponseEntity.ok(wordFilterService.getNegativeIndicators());
    }

    /**
     * Get positive words list.
     */
    @GetMapping("/positive")
    public ResponseEntity<Set<String>> getPositiveWords() {
        return ResponseEntity.ok(wordFilterService.getPositiveWords());
    }

    /**
     * Get sensitive subjects list.
     */
    @GetMapping("/sensitive")
    public ResponseEntity<Set<String>> getSensitiveSubjects() {
        return ResponseEntity.ok(wordFilterService.getSensitiveSubjects());
    }

    /**
     * Reload all filters from files.
     */
    @PostMapping("/reload")
    public ResponseEntity<Map<String, String>> reloadFilters() {
        wordFilterService.reloadAllFilters();
        Map<String, String> response = new HashMap<>();
        response.put("message", "Filters reloaded successfully");
        return ResponseEntity.ok(response);
    }

    /**
     * Check if text contains any bad words.
     */
    @PostMapping("/check")
    public ResponseEntity<Map<String, Object>> checkText(@RequestBody Map<String, String> request) {
        String text = request.get("text");
        
        Map<String, Object> result = new HashMap<>();
        result.put("containsToxic", wordFilterService.containsToxicWord(text));
        result.put("containsNegative", wordFilterService.containsNegativeIndicator(text));
        result.put("containsPositive", wordFilterService.containsPositiveWord(text));
        result.put("toxicCount", wordFilterService.countMatches(text, wordFilterService.getToxicWords()));
        result.put("negativeCount", wordFilterService.countMatches(text, wordFilterService.getNegativeIndicators()));
        result.put("positiveCount", wordFilterService.countMatches(text, wordFilterService.getPositiveWords()));
        
        return ResponseEntity.ok(result);
    }
}
