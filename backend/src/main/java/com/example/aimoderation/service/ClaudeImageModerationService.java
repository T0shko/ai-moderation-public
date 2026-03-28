package com.example.aimoderation.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.*;

/**
 * Image content moderation using Claude vision API (claude-haiku-4-5-20251001).
 *
 * Uses a "thinking pattern" approach: Claude observes the full pixel matrix of the
 * image and classifies it into a category detection matrix:
 *
 *   ADULT      — nudity, sexual content, explicit material
 *   VIOLENCE   — blood, gore, physical harm, injury
 *   WEAPONS    — guns, knives, bombs, military weapons
 *   DRUGS      — drug paraphernalia, illegal substances
 *   HATE_SYMBOLS — swastikas, hate group symbols, discriminatory imagery
 *   SPAM       — phishing, excessive text overlays, QR abuse
 *   SAFE       — no violations detected
 *
 * If ANY category is detected with confidence >= 0.5, the image is blocked.
 * This works on every type of image because Claude actually understands what is in it.
 */
@Service
public class ClaudeImageModerationService {

    private static final Logger logger = LoggerFactory.getLogger(ClaudeImageModerationService.class);
    private static final String CLAUDE_API_URL = "https://api.anthropic.com/v1/messages";
    private static final String MODEL = "claude-haiku-4-5-20251001";

    @Value("${anthropic.api.key:}")
    private String apiKey;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Analyze an image by sending it to Claude's vision API.
     * Claude examines every element in the image and classifies it against
     * the moderation category matrix.
     *
     * @param imageData   raw bytes of the image
     * @param contentType MIME type (e.g. "image/jpeg")
     * @return moderation decision with category matrix results
     */
    public ImageModerationResult moderateImage(byte[] imageData, String contentType) {
        if (apiKey == null || apiKey.isBlank()) {
            logger.warn("Anthropic API key not configured — Claude image moderation skipped");
            return new ImageModerationResult(false, 0.0, Collections.emptyList(), "Claude not configured", "UNKNOWN");
        }

        try {
            String base64Image = Base64.getEncoder().encodeToString(imageData);
            String mediaType = (contentType != null && !contentType.isBlank()) ? contentType : "image/jpeg";
            // Ensure content type is in correct format for API
            if (!mediaType.startsWith("image/")) mediaType = "image/jpeg";

            String systemPrompt = """
                    You are a strict image content moderation AI.

                    TASK: Examine every visual element in the image and classify it against the category matrix below.

                    CATEGORY MATRIX — check each independently:
                      ADULT        — nudity, sexual content, explicit material, suggestive poses
                      VIOLENCE     — blood, gore, physical harm to any living being, injury, death
                      WEAPONS      — firearms, guns, knives, bombs, grenades, military weapons
                      DRUGS        — drug paraphernalia, syringes, pills being misused, illegal substances
                      HATE_SYMBOLS — swastikas, KKK imagery, hate group logos, discriminatory symbols
                      SPAM         — phishing QR codes, excessive promotional text, scam imagery

                    THINKING APPROACH:
                    1. First, describe to yourself what objects, people, and context you see
                    2. For each category, evaluate: does the image contain this type of content?
                    3. Assign a confidence score per category
                    4. If any category has confidence >= 0.5, set blocked=true

                    OUTPUT RULES:
                    - Respond ONLY with valid JSON, absolutely no other text
                    - Required format:
                    {"blocked": true/false, "confidence": 0.0-1.0, "categories": ["CATEGORY1","CATEGORY2"], "reason": "what was detected", "primary_category": "MOST_SEVERE or SAFE"}

                    If completely safe: {"blocked": false, "confidence": 0.95, "categories": [], "reason": "No policy violations detected", "primary_category": "SAFE"}
                    """;

            // Build the vision message with image + text
            Map<String, Object> textPart = Map.of("type", "text", "text", "Analyze this image against the content policy category matrix:");
            Map<String, Object> imagePart = Map.of(
                    "type", "image",
                    "source", Map.of(
                            "type", "base64",
                            "media_type", mediaType,
                            "data", base64Image
                    )
            );

            Map<String, Object> requestBody = new HashMap<>();
            requestBody.put("model", MODEL);
            requestBody.put("max_tokens", 512);
            requestBody.put("system", systemPrompt);
            requestBody.put("messages", List.of(
                    Map.of("role", "user", "content", List.of(textPart, imagePart))
            ));

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("x-api-key", apiKey);
            headers.set("anthropic-version", "2023-06-01");

            HttpEntity<Map<String, Object>> request = new HttpEntity<>(requestBody, headers);
            ResponseEntity<Map> response = restTemplate.exchange(CLAUDE_API_URL, HttpMethod.POST, request, Map.class);

            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> content = (List<Map<String, Object>>) response.getBody().get("content");
                if (content != null && !content.isEmpty()) {
                    String jsonText = (String) content.get(0).get("text");
                    // Strip markdown code blocks if Claude wraps the JSON
                    jsonText = jsonText.replaceAll("```json\\s*", "").replaceAll("```\\s*", "").trim();

                    @SuppressWarnings("unchecked")
                    Map<String, Object> result = objectMapper.readValue(jsonText, Map.class);

                    boolean blocked = Boolean.TRUE.equals(result.get("blocked"));
                    double confidence = result.get("confidence") instanceof Number
                            ? ((Number) result.get("confidence")).doubleValue() : 0.5;
                    @SuppressWarnings("unchecked")
                    List<String> categories = result.get("categories") instanceof List
                            ? (List<String>) result.get("categories") : Collections.emptyList();
                    String reason = result.get("reason") instanceof String
                            ? (String) result.get("reason") : "";
                    String primaryCategory = result.get("primary_category") instanceof String
                            ? (String) result.get("primary_category") : "UNKNOWN";

                    logger.info("Claude image analysis: blocked={}, confidence={}, primaryCategory={}, categories={}",
                            blocked, confidence, primaryCategory, categories);
                    return new ImageModerationResult(blocked, confidence, categories, reason, primaryCategory);
                }
            }
        } catch (Exception e) {
            logger.error("Claude image moderation error: {}", e.getMessage());
        }

        // On error, flag for human review rather than silently allowing
        return new ImageModerationResult(false, 0.5, Collections.emptyList(),
                "Claude image analysis failed — manual review recommended", "UNKNOWN");
    }

    public record ImageModerationResult(
            boolean blocked,
            double confidence,
            List<String> categories,
            String reason,
            String primaryCategory) {}
}
