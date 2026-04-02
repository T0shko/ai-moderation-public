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
import com.example.aimoderation.repository.CommentRepository;
import com.example.aimoderation.model.Comment;
import com.example.aimoderation.model.CommentStatus;
import org.springframework.beans.factory.annotation.Autowired;

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

    @Autowired
    private CommentRepository commentRepository;

    // OpenNLP components
    private SimpleTokenizer tokenizer;
    private SentenceDetectorME sentenceDetector;

    // Knowledge base for moderation-related questions — conversational style
    private static final Map<String, String> KNOWLEDGE_BASE = Map.ofEntries(
            Map.entry("moderation", "So content moderation is basically how we keep things safe around here. We use AI to catch harmful stuff like hate speech, violence, spam, and explicit content. The cool part is we don't rely on just one model — we run an ensemble of them together, so if one misses something, another catches it."),
            Map.entry("sentiment", "Sentiment analysis is how we figure out the \"mood\" behind a message. We look at whether text feels positive, neutral, or negative using multiple signals — toxic word detection, learned patterns from past decisions, negative indicators, and positive word scoring. It all gets combined into a confidence score."),
            Map.entry("image", "For images, we run a 2-layer analysis. First, HuggingFace's CLIP model does zero-shot classification to detect things like NSFW content, weapons, violence, etc. Then our custom local algorithm breaks the image into a spatial grid and analyzes pixel patterns — skin tones, blood-red areas, dark silhouettes, and text overlays. If either layer flags something, the image gets reviewed."),
            Map.entry("ensemble", "Our ensemble approach is all about \"better safe than sorry.\" We run multiple models on every piece of content, and if ANY one of them flags it, it goes to a human moderator. Sure, it means a few extra manual reviews, but it dramatically reduces the chance of harmful content slipping through."),
            Map.entry("nlp", "We use Natural Language Processing for things like breaking text into tokens, detecting sentence boundaries, and extracting keywords. OpenNLP handles the local processing, and HuggingFace adds an AI-powered layer on top. Together they help us understand not just what words are used, but the intent behind them."),
            Map.entry("help", "Happy to help! I know a lot about content moderation, sentiment analysis, image recognition, and NLP. You can also ask me about recent posts in the community or how specific features work. What's on your mind?"),
            Map.entry("toxic", "Toxic content detection is pretty thorough. We use word filters that can see through tricks like leet-speak (e.g., \"h4te\") and character substitution. We also learn from moderator decisions over time. The rule is strict: even a single toxic word gets the content flagged, because context can be hard to judge automatically."),
            Map.entry("safety", "Content safety here works in layers. First, AI scans everything automatically and assigns confidence scores. High-confidence violations get blocked right away. Edge cases go to human moderators for review. And the system keeps learning from those moderator decisions, so it gets smarter over time.")
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
                if (pastUserInputs.size() > 5) pastUserInputs = pastUserInputs.subList(pastUserInputs.size() - 5, pastUserInputs.size());
                if (generatedResponses.size() > 5) generatedResponses = generatedResponses.subList(generatedResponses.size() - 5, generatedResponses.size());

                // Inject feed awareness
                if (message.toLowerCase().contains("post") || message.toLowerCase().contains("feed") || message.toLowerCase().contains("comment")) {
                    List<Comment> recent = commentRepository.findByStatus(CommentStatus.APPROVED);
                    if (!recent.isEmpty()) {
                        String recentPosts = recent.stream().sorted(Comparator.comparing(Comment::getCreatedAt).reversed()).limit(3)
                             .map(c -> c.getContent()).collect(Collectors.joining(" | "));
                        inputs.put("text", message + " (Context: Recent posts are: " + recentPosts + ")");
                    }
                }

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
        String msgLower = message.toLowerCase();

        // Let AI know about recent approved posts if requested
        if (msgLower.contains("post") || msgLower.contains("feed") || msgLower.contains("comment") || msgLower.contains("recent") || msgLower.contains("approve")) {
            List<Comment> recent = commentRepository.findByStatus(CommentStatus.APPROVED);
            if (!recent.isEmpty()) {
                StringBuilder sb = new StringBuilder("Here's what's been happening in the community lately:\n\n");
                recent.stream().sorted(Comparator.comparing(Comment::getCreatedAt).reversed()).limit(3).forEach(c -> {
                    sb.append("  \u2022 ").append(c.getAuthor().getUsername()).append(": \"").append(c.getContent()).append("\"\n");
                });
                return sb.toString();
            }
        }

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
            case "greeting" -> {
                String[] greetings = {
                    "Hey there! I'm the AI moderation assistant. I can walk you through how moderation works, explain sentiment analysis, or chat about image recognition. What are you curious about?",
                    "Hi! Good to see you. I'm here to help with anything related to content moderation, AI analysis, or how this platform works. What would you like to know?",
                    "Hello! I'm your moderation assistant. Feel free to ask me about how we keep content safe, how sentiment analysis works, or anything else on your mind."
                };
                response.append(greetings[new Random().nextInt(greetings.length)]);
            }
            case "gratitude" -> {
                String[] thanks = {
                    "Glad I could help! Let me know if anything else comes up.",
                    "Anytime! Don't hesitate to ask if you have more questions.",
                    "You're welcome! I'm always here if you need more info."
                };
                response.append(thanks[new Random().nextInt(thanks.length)]);
            }
            case "help_request" -> {
                response.append("Of course! Here's what I can help with:\n\n");
                response.append("  \u2022 How content moderation works and our AI pipeline\n");
                response.append("  \u2022 Sentiment analysis — how we classify text tone\n");
                response.append("  \u2022 Image recognition and our detection layers\n");
                response.append("  \u2022 NLP features and how text is processed\n");
                response.append("  \u2022 Recent posts and community activity\n\n");
                response.append("Just ask away!");
            }
            default -> {
                if (!matchedTopics.isEmpty()) {
                    response.append(String.join("\n\n", matchedTopics));
                } else {
                    // Friendly fallback — no robotic token counts
                    String[] fallbacks = {
                        "That's an interesting question! I'm mainly focused on content moderation and AI analysis topics. Try asking me about how moderation works, sentiment analysis, image recognition, or what's happening in the community feed.",
                        "I'm not sure I have a great answer for that one — my expertise is in content moderation and AI safety. You could ask me about how our ensemble system works, how images are analyzed, or what the latest community posts look like.",
                        "Hmm, that's a bit outside my wheelhouse. I know a lot about moderation, sentiment analysis, image detection, and NLP though. Want to explore any of those?"
                    };
                    response.append(fallbacks[new Random().nextInt(fallbacks.length)]);
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

        // If we have a good NLP knowledge-base response, prefer it (more relevant)
        boolean nlpHasSubstance = nlpResponse != null
                && !nlpResponse.contains("outside my wheelhouse")
                && !nlpResponse.contains("interesting question");

        if (nlpHasSubstance) {
            // Knowledge base response is relevant — use it, optionally enriched by HF
            if (hfAvailable && hfResponse.length() > 20) {
                return nlpResponse + "\n\nBy the way — " + hfResponse;
            }
            return nlpResponse;
        }

        // Fall back to HuggingFace if NLP didn't have a knowledge-base match
        if (hfAvailable && hfResponse.length() > 10) {
            return hfResponse;
        }

        return nlpResponse != null ? nlpResponse :
                "Hey! I'm your AI moderation assistant. Ask me about content moderation, sentiment analysis, image recognition, or what's happening in the community!";
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
