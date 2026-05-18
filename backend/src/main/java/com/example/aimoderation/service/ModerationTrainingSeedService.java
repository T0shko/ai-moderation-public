package com.example.aimoderation.service;

import com.example.aimoderation.model.ModerationTrainingData;
import com.example.aimoderation.repository.ModerationTrainingDataRepository;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;

/**
 * Seeds learned-negative phrases from classpath on first run (Bulgarian + EN slang).
 */
@Service
public class ModerationTrainingSeedService {

    private static final Logger logger = LoggerFactory.getLogger(ModerationTrainingSeedService.class);

    @Value("${filter.training-seed.path:filters/training-seed-negative.txt}")
    private String seedPath;

    @Autowired
    private ModerationTrainingDataRepository trainingDataRepository;

    @Autowired
    private SentimentAnalysisService sentimentAnalysisService;

    @PostConstruct
    public void seedIfEmpty() {
        if (trainingDataRepository.count() > 0) {
            return;
        }
        try {
            ClassPathResource resource = new ClassPathResource(seedPath);
            if (!resource.exists()) {
                logger.warn("Training seed file not found: {}", seedPath);
                return;
            }
            int rows = 0;
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(resource.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    String trimmed = line.trim();
                    if (trimmed.isEmpty() || trimmed.startsWith("#")) {
                        continue;
                    }
                    ModerationTrainingData row = new ModerationTrainingData();
                    row.setContent(trimmed);
                    row.setLabel("NEGATIVE");
                    row.setCreatedAt(LocalDateTime.now());
                    trainingDataRepository.save(row);
                    rows++;
                }
            }
            sentimentAnalysisService.invalidateLearnedCache();
            logger.info("Seeded {} moderation training phrase rows from {}", rows, seedPath);
        } catch (Exception e) {
            logger.error("Failed to seed moderation training data: {}", e.getMessage(), e);
        }
    }
}
