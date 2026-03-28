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
 * Text content moderation using Claude AI (claude-haiku-4-5-20251001).
 * Detects: hate speech, threats, explicit content, harassment, spam, toxicity.
 *
 * Runs in ensemble with the word-filter service — if EITHER flags content, it gets blocked.
 */
@Service
public class ClaudeTextModerationService {

    private static final Logger logger = LoggerFactory.getLogger(ClaudeTextModerationService.class);
    private static final String CLAUDE_API_URL = "https://api.anthropic.com/v1/messages";
    private static final String MODEL = "claude-haiku-4-5-20251001";

    @Value("${anthropic.api.key:}")
    private String apiKey;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Analyze text for policy violations using Claude AI.
     * Returns a decision with detected categories and reason.
     */
    public TextModerationResult moderateText(String text) {
        if (apiKey == null || apiKey.isBlank()) {
            logger.warn("Anthropic API key not configured — Claude text moderation skipped");
            return new TextModerationResult(false, 0.0, Collections.emptyList(), "Claude not configured");
        }

        try {
            String systemPrompt = """
                    You are a strict content moderation AI. Analyze the provided text and determine whether it violates content policies.

                    Check for these violation categories:
                    - HATE_SPEECH: racist, sexist, homophobic, or otherwise discriminatory/hateful language
                    - THREATS: direct or indirect threats of violence against any person or group
                    - EXPLICIT: sexual, pornographic, or grossly graphic content
                    - HARASSMENT: bullying, personal attacks, sustained intimidation
                    - SPAM: repetitive, nonsensical, or unsolicited promotional content
                    - TOXICITY: extremely offensive, abusive, or degrading language

                    Rules:
                    - If ANY category is detected with confidence >= 0.5, set "blocked": true
                    - Be strict — borderline content should be blocked
                    - Respond ONLY with valid JSON, no other text

                    Required JSON format:
                    {"blocked": true, "confidence": 0.85, "categories": ["HATE_SPEECH"], "reason": "Contains racial slur targeting a group"}
                    """;

            Map<String, Object> requestBody = new HashMap<>();
            requestBody.put("model", MODEL);
            requestBody.put("max_tokens", 256);
            requestBody.put("system", systemPrompt);
            requestBody.put("messages", List.of(
                    Map.of("role", "user", "content", "Analyze this text: " + text)
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
                    // Strip any markdown code blocks if Claude wraps JSON
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

                    logger.info("Claude text analysis: blocked={}, confidence={}, categories={}", blocked, confidence, categories);
                    return new TextModerationResult(blocked, confidence, categories, reason);
                }
            }
        } catch (Exception e) {
            logger.error("Claude text moderation error: {}", e.getMessage());
        }

        // On error, don't block — let word-filter handle it
        return new TextModerationResult(false, 0.0, Collections.emptyList(), "Claude analysis failed");
    }

    public record TextModerationResult(boolean blocked, double confidence, List<String> categories, String reason) {}
}
