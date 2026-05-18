package com.example.aimoderation.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.*;

/**
 * Optional Groq LLM judge for borderline text — understands Bulgarian/English context.
 */
@Service
public class TextContextAiService {

    private static final Logger logger = LoggerFactory.getLogger(TextContextAiService.class);
    private static final String GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";

    private static final String SYSTEM_PROMPT = """
            You are a strict but context-aware content moderator for a Bulgarian and English social app.
            Classify the user message into exactly one category:
            - SAFE: acceptable, including compliments and jokes without harassment (e.g. "maika ti e hubava" = your mom is beautiful).
            - TOXIC: profanity, threats, hate, sexual harassment, insults, self-harm encouragement.
            - REVIEW: truly ambiguous; cannot decide.
            Reply with only one word: SAFE, TOXIC, or REVIEW. No explanation.
            """;

    @Value("${groq.api.key:}")
    private String groqApiKey;

    @Value("${chat.groq.model:llama-3.1-8b-instant}")
    private String groqModel;

    @Value("${moderation.text.ai-context.enabled:true}")
    private boolean aiContextEnabled;

    private final RestTemplate restTemplate = new RestTemplate();

    public enum AiVerdict {
        SAFE, TOXIC, REVIEW, UNAVAILABLE
    }

    public boolean isAvailable() {
        return aiContextEnabled && groqApiKey != null && !groqApiKey.isBlank();
    }

    @SuppressWarnings("unchecked")
    public AiVerdict adjudicate(String originalText) {
        if (!isAvailable() || originalText == null || originalText.isBlank()) {
            return AiVerdict.UNAVAILABLE;
        }
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("model", groqModel);
            body.put("temperature", 0.0);
            body.put("max_tokens", 8);
            body.put("messages", List.of(
                    Map.of("role", "system", "content", SYSTEM_PROMPT),
                    Map.of("role", "user", "content", originalText)));

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth(groqApiKey);

            ResponseEntity<Map> response = restTemplate.exchange(
                    GROQ_URL, HttpMethod.POST, new HttpEntity<>(body, headers), Map.class);

            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                String raw = extractContent(response.getBody());
                if (raw != null) {
                    String word = raw.trim().toUpperCase(Locale.ROOT).replaceAll("[^A-Z]", "");
                    return switch (word) {
                        case "SAFE" -> AiVerdict.SAFE;
                        case "TOXIC" -> AiVerdict.TOXIC;
                        case "REVIEW" -> AiVerdict.REVIEW;
                        default -> AiVerdict.REVIEW;
                    };
                }
            }
        } catch (Exception e) {
            logger.warn("Text context AI adjudication failed: {}", e.getMessage());
        }
        return AiVerdict.UNAVAILABLE;
    }

    @SuppressWarnings("unchecked")
    private String extractContent(Map<String, Object> root) {
        Object choices = root.get("choices");
        if (!(choices instanceof List<?> list) || list.isEmpty()) {
            return null;
        }
        Object first = list.get(0);
        if (!(first instanceof Map<?, ?> choice)) {
            return null;
        }
        Object message = choice.get("message");
        if (!(message instanceof Map<?, ?> msg)) {
            return null;
        }
        Object content = msg.get("content");
        return content instanceof String s ? s : null;
    }
}
