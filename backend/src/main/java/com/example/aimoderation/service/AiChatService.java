package com.example.aimoderation.service;

import opennlp.tools.sentdetect.SentenceDetectorME;
import opennlp.tools.sentdetect.SentenceModel;
import opennlp.tools.tokenize.SimpleTokenizer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import jakarta.annotation.PostConstruct;
import java.io.InputStream;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * AI Chat Service using FREE models only:
 *
 * 1. HuggingFace Inference API (free tier) - conversational models
 * 2. OpenNLP - local NLP processing (tokenization, sentence detection, keyword extraction)
 * 3. Combined mode - merges HuggingFace response with NLP-enriched context
 *
 * Users can choose any single provider or combine all of them.
 */
@Service
public class AiChatService {

    private static final Logger logger = LoggerFactory.getLogger(AiChatService.class);

    private static final String HF_API_BASE = "https://api-inference.huggingface.co/models/";

    @Value("${huggingface.api.token:}")
    private String hfApiToken;

    @Value("${chat.default-provider:combined}")
    private String defaultProvider;

    @Value("${chat.huggingface.model:microsoft/DialoGPT-medium}")
    private String hfModel;

    @Value("${chat.huggingface.fallback-model:facebook/blenderbot-400M-distill}")
    private String hfFallbackModel;

    private final RestTemplate restTemplate = new RestTemplate();

    // Simple conversation memory per user (last 10 messages)
    private final ConcurrentHashMap<String, List<Message>> conversationHistory = new ConcurrentHashMap<>();

    // OpenNLP components
    private SimpleTokenizer tokenizer;
    private SentenceDetectorME sentenceDetector;

    // Knowledge base for moderation-related questions
    private static final Map<String, String> KNOWLEDGE_BASE = Map.ofEntries(
            Map.entry("moderation", "Content moderation uses AI to detect harmful content including hate speech, violence, spam, and explicit material. Our system uses an ensemble of models for maximum accuracy."),
            Map.entry("sentiment", "Sentiment analysis classifies text as POSITIVE, NEUTRAL, or NEGATIVE. We use a multi-phase approach: toxic word detection, learned patterns, negative indicators, and positive word scoring."),
            Map.entry("image", "Image moderation uses a 3-layer ensemble: Claude Vision for semantic understanding, HuggingFace for NSFW/object detection, and a local spatial grid algorithm for pixel-level analysis."),
            Map.entry("ensemble", "Ensemble learning combines multiple models for better accuracy. If ANY model flags content, it goes for human review. This reduces false negatives at the cost of slightly more manual reviews."),
            Map.entry("nlp", "Natural Language Processing (NLP) includes tokenization, sentence detection, sentiment analysis, and named entity recognition. We use OpenNLP for local processing and HuggingFace for AI-powered analysis."),
            Map.entry("help", "I can help you understand content moderation, sentiment analysis, image recognition, NLP concepts, and how to use this application. Just ask me anything!"),
            Map.entry("toxic", "Toxic content detection uses word filters, leet-speak normalization, obfuscation detection, and learned patterns from moderator decisions. Even one toxic word triggers flagging regardless of context."),
            Map.entry("safety", "Content safety involves multiple layers: automated AI detection, confidence scoring, human moderator review for edge cases, and continuous learning from moderator decisions.")
    );

    @PostConstruct
    public void init() {
        tokenizer = SimpleTokenizer.INSTANCE;
        try {
            InputStream modelIn = getClass().getResourceAsStream("/opennlp/en-sent.bin");
            if (modelIn != null) {
                SentenceModel sentModel = new SentenceModel(modelIn);
                sentenceDetector = new SentenceDetectorME(sentModel);
                logger.info("OpenNLP sentence detector loaded successfully");
            } else {
                logger.warn("OpenNLP sentence model not found - using fallback sentence detection");
            }
        } catch (Exception e) {
            logger.warn("Failed to load OpenNLP models: {} - using fallback", e.getMessage());
        }
    }

    /**
     * Process a chat message using the specified provider(s).
     *
     * @param username  the user sending the message
     * @param message   the user's message
     * @param provider  "huggingface", "opennlp", or "combined"
     * @return ChatResponse with the AI's reply and metadata
     */
    public ChatResponse chat(String username, String message, String provider) {
        if (provider == null || provider.isBlank()) {
            provider = defaultProvider;
        }

        // Store user message in history
        addToHistory(username, new Message("user", message));

        List<String> modelsUsed = new ArrayList<>();
        String response;
        Map<String, Object> metadata = new LinkedHashMap<>();

        // NLP analysis is always performed for metadata
        NlpAnalysis nlpAnalysis = performNlpAnalysis(message);
        metadata.put("tokens", nlpAnalysis.tokens);
        metadata.put("sentences", nlpAnalysis.sentenceCount);
        metadata.put("keywords", nlpAnalysis.keywords);
        metadata.put("intent", nlpAnalysis.intent);

        switch (provider.toLowerCase()) {
            case "huggingface" -> {
                response = queryHuggingFace(message, username);
                modelsUsed.add("HuggingFace/" + hfModel);
            }
            case "opennlp" -> {
                response = generateNlpResponse(message, nlpAnalysis);
                modelsUsed.add("OpenNLP-local");
            }
            case "combined" -> {
                // Get responses from all providers and merge
                String hfResponse = queryHuggingFace(message, username);
                String nlpResponse = generateNlpResponse(message, nlpAnalysis);
                response = combineResponses(hfResponse, nlpResponse, nlpAnalysis);
                modelsUsed.add("HuggingFace/" + hfModel);
                modelsUsed.add("OpenNLP-local");
                modelsUsed.add("KnowledgeBase");
            }
            default -> {
                response = generateNlpResponse(message, nlpAnalysis);
                modelsUsed.add("OpenNLP-local");
            }
        }

        // Store AI response in history
        addToHistory(username, new Message("assistant", response));

        metadata.put("provider", provider);
        metadata.put("modelsUsed", modelsUsed);

        return new ChatResponse(response, modelsUsed, metadata);
    }

    /**
     * Get conversation history for a user.
     */
    public List<Message> getHistory(String username) {
        return conversationHistory.getOrDefault(username, Collections.emptyList());
    }

    /**
     * Clear conversation history for a user.
     */
    public void clearHistory(String username) {
        conversationHistory.remove(username);
    }

    // =========================================================================
    // HUGGINGFACE PROVIDER (FREE)
    // =========================================================================

    private String queryHuggingFace(String message, String username) {
        if (hfApiToken == null || hfApiToken.isBlank()) {
            return "HuggingFace API is not configured. Please set HUGGINGFACE_API_TOKEN to enable AI chat.";
        }

        // Try primary model, then fallback
        String result = callHuggingFaceModel(message, hfModel, username);
        if (result == null) {
            result = callHuggingFaceModel(message, hfFallbackModel, username);
        }
        return result != null ? result : "I'm having trouble connecting to the AI service. Please try again.";
    }

    @SuppressWarnings("unchecked")
    private String callHuggingFaceModel(String message, String model, String username) {
        try {
            String url = HF_API_BASE + model;

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth(hfApiToken);

            // Build conversation context from history
            List<Message> history = conversationHistory.getOrDefault(username, Collections.emptyList());
            Map<String, Object> body = new LinkedHashMap<>();

            if (model.contains("blenderbot") || model.contains("DialoGPT")) {
                // Conversational pipeline format
                Map<String, Object> inputs = new LinkedHashMap<>();
                inputs.put("text", message);

                List<String> pastUserInputs = new ArrayList<>();
                List<String> generatedResponses = new ArrayList<>();
                for (Message msg : history) {
                    if ("user".equals(msg.role)) pastUserInputs.add(msg.content);
                    else generatedResponses.add(msg.content);
                }
                // Keep last 5 turns for context
                if (pastUserInputs.size() > 5) pastUserInputs = pastUserInputs.subList(pastUserInputs.size() - 5, pastUserInputs.size());
                if (generatedResponses.size() > 5) generatedResponses = generatedResponses.subList(generatedResponses.size() - 5, generatedResponses.size());

                inputs.put("past_user_inputs", pastUserInputs);
                inputs.put("generated_responses", generatedResponses);
                body.put("inputs", inputs);
            } else {
                body.put("inputs", message);
            }

            body.put("options", Map.of("wait_for_model", true));

            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);
            ResponseEntity<Object> response = restTemplate.exchange(url, HttpMethod.POST, request, Object.class);

            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                Object respBody = response.getBody();
                if (respBody instanceof Map) {
                    Map<String, Object> map = (Map<String, Object>) respBody;
                    if (map.containsKey("generated_text")) {
                        return (String) map.get("generated_text");
                    }
                    if (map.containsKey("conversation")) {
                        Map<String, Object> conv = (Map<String, Object>) map.get("conversation");
                        if (conv != null && conv.containsKey("generated_responses")) {
                            List<String> responses = (List<String>) conv.get("generated_responses");
                            if (!responses.isEmpty()) {
                                return responses.get(responses.size() - 1);
                            }
                        }
                    }
                } else if (respBody instanceof List) {
                    List<?> list = (List<?>) respBody;
                    if (!list.isEmpty()) {
                        Object first = list.get(0);
                        if (first instanceof Map) {
                            return (String) ((Map<String, Object>) first).get("generated_text");
                        }
                        return first.toString();
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("HuggingFace model {} failed: {}", model, e.getMessage());
        }
        return null;
    }

    // =========================================================================
    // OPENNLP PROVIDER (LOCAL, FREE)
    // =========================================================================

    private NlpAnalysis performNlpAnalysis(String message) {
        String[] tokens = tokenizer.tokenize(message);
        int sentenceCount = 1;
        if (sentenceDetector != null) {
            sentenceCount = sentenceDetector.sentDetect(message).length;
        } else {
            // Fallback: count periods, question marks, exclamation marks
            sentenceCount = Math.max(1, (int) message.chars().filter(c -> c == '.' || c == '?' || c == '!').count());
        }

        // Extract keywords (non-stopword tokens > 3 chars)
        Set<String> stopWords = Set.of("the", "a", "an", "is", "are", "was", "were", "be", "been",
                "being", "have", "has", "had", "do", "does", "did", "will", "would", "could",
                "should", "may", "might", "can", "shall", "this", "that", "these", "those",
                "and", "but", "or", "nor", "for", "yet", "so", "in", "on", "at", "to", "from",
                "with", "about", "into", "through", "during", "before", "after", "above", "below",
                "between", "not", "what", "how", "when", "where", "who", "which", "why", "it", "its");

        List<String> keywords = Arrays.stream(tokens)
                .map(String::toLowerCase)
                .filter(t -> t.length() > 3 && !stopWords.contains(t) && t.matches("[a-zA-Z]+"))
                .distinct()
                .limit(10)
                .collect(Collectors.toList());

        // Detect intent
        String intent = detectIntent(message.toLowerCase(), keywords);

        return new NlpAnalysis(Arrays.asList(tokens), sentenceCount, keywords, intent);
    }

    private String detectIntent(String message, List<String> keywords) {
        if (message.contains("?") || message.startsWith("what") || message.startsWith("how")
                || message.startsWith("why") || message.startsWith("when") || message.startsWith("where")
                || message.startsWith("who") || message.startsWith("can") || message.startsWith("does")) {
            return "question";
        }
        if (message.startsWith("help") || message.contains("help me") || message.contains("assist")) {
            return "help_request";
        }
        if (message.contains("hello") || message.contains("hi ") || message.startsWith("hi")
                || message.contains("hey") || message.contains("greetings")) {
            return "greeting";
        }
        if (message.contains("thank") || message.contains("thanks") || message.contains("appreciate")) {
            return "gratitude";
        }
        if (message.contains("explain") || message.contains("tell me about") || message.contains("describe")) {
            return "explanation_request";
        }
        return "statement";
    }

    private String generateNlpResponse(String message, NlpAnalysis analysis) {
        // Check knowledge base for relevant topics
        String lowerMessage = message.toLowerCase();
        List<String> matchedTopics = new ArrayList<>();

        for (Map.Entry<String, String> entry : KNOWLEDGE_BASE.entrySet()) {
            if (lowerMessage.contains(entry.getKey()) ||
                    analysis.keywords.stream().anyMatch(k -> k.contains(entry.getKey()))) {
                matchedTopics.add(entry.getValue());
            }
        }

        StringBuilder response = new StringBuilder();

        // Handle based on intent
        switch (analysis.intent) {
            case "greeting" -> response.append("Hello! I'm your AI moderation assistant. I can help you understand content moderation, sentiment analysis, image recognition, and NLP concepts. What would you like to know?");
            case "gratitude" -> response.append("You're welcome! Feel free to ask if you have more questions about moderation or AI.");
            case "help_request" -> {
                response.append("I'm here to help! Here's what I can assist with:\n\n");
                response.append("- Content moderation concepts and how our system works\n");
                response.append("- Sentiment analysis and how text is classified\n");
                response.append("- Image recognition and our 3-layer detection system\n");
                response.append("- NLP (Natural Language Processing) features\n");
                response.append("- How the ensemble model combines multiple AI systems\n\n");
                response.append("Just ask me about any of these topics!");
            }
            default -> {
                if (!matchedTopics.isEmpty()) {
                    response.append(String.join("\n\n", matchedTopics));
                } else {
                    response.append("I analyzed your message (").append(analysis.tokens.size())
                            .append(" tokens, ").append(analysis.sentenceCount).append(" sentence(s)). ");
                    if (!analysis.keywords.isEmpty()) {
                        response.append("Key topics: ").append(String.join(", ", analysis.keywords)).append(". ");
                    }
                    response.append("\n\nI'm specialized in content moderation topics. Try asking about: moderation, sentiment analysis, image recognition, NLP, or how our ensemble system works.");
                }
            }
        }

        return response.toString();
    }

    // =========================================================================
    // COMBINED MODE
    // =========================================================================

    private String combineResponses(String hfResponse, String nlpResponse, NlpAnalysis analysis) {
        boolean hfAvailable = hfResponse != null
                && !hfResponse.contains("not configured")
                && !hfResponse.contains("trouble connecting");

        StringBuilder combined = new StringBuilder();

        // If we got a good HuggingFace response, lead with it
        if (hfAvailable && hfResponse.length() > 10) {
            combined.append(hfResponse);
        }

        // Always add NLP-enriched knowledge base content if relevant
        if (nlpResponse != null && !nlpResponse.contains("I analyzed your message")) {
            if (combined.length() > 0) {
                combined.append("\n\n---\n\n");
            }
            combined.append(nlpResponse);
        }

        if (combined.isEmpty()) {
            return nlpResponse != null ? nlpResponse :
                    "I'm your AI moderation assistant. Ask me about content moderation, sentiment analysis, or image recognition!";
        }

        return combined.toString();
    }

    // =========================================================================
    // CONVERSATION HISTORY
    // =========================================================================

    private void addToHistory(String username, Message message) {
        conversationHistory.computeIfAbsent(username, k -> Collections.synchronizedList(new ArrayList<>()));
        List<Message> history = conversationHistory.get(username);
        history.add(message);
        // Keep last 20 messages
        while (history.size() > 20) {
            history.remove(0);
        }
    }

    // =========================================================================
    // DATA CLASSES
    // =========================================================================

    public record Message(String role, String content) {}

    public record ChatResponse(
            String response,
            List<String> modelsUsed,
            Map<String, Object> metadata
    ) {}

    private record NlpAnalysis(
            List<String> tokens,
            int sentenceCount,
            List<String> keywords,
            String intent
    ) {}
}
