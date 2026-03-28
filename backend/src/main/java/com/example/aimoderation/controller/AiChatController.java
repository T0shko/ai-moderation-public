package com.example.aimoderation.controller;

import com.example.aimoderation.security.services.UserDetailsImpl;
import com.example.aimoderation.service.AiChatService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * REST controller for AI Chat functionality.
 * All endpoints are free - uses HuggingFace free tier, OpenNLP (local), or combined.
 */
@RestController
@RequestMapping("/api/chat")
@CrossOrigin(origins = "*", maxAge = 3600)
public class AiChatController {

    @Autowired
    private AiChatService aiChatService;

    /**
     * Send a message to the AI chatbot.
     *
     * @param request  { "message": "...", "provider": "huggingface|opennlp|combined" }
     * @param userDetails authenticated user
     * @return AI response with metadata
     */
    @PostMapping
    public ResponseEntity<?> chat(
            @RequestBody Map<String, String> request,
            @AuthenticationPrincipal UserDetailsImpl userDetails) {

        String message = request.get("message");
        String provider = request.getOrDefault("provider", "combined");

        if (message == null || message.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Message cannot be empty"));
        }

        AiChatService.ChatResponse response = aiChatService.chat(
                userDetails.getUsername(), message.trim(), provider);

        return ResponseEntity.ok(Map.of(
                "response", response.response(),
                "modelsUsed", response.modelsUsed(),
                "metadata", response.metadata()
        ));
    }

    /**
     * Get conversation history for the current user.
     */
    @GetMapping("/history")
    public ResponseEntity<?> getHistory(@AuthenticationPrincipal UserDetailsImpl userDetails) {
        List<AiChatService.Message> history = aiChatService.getHistory(userDetails.getUsername());
        return ResponseEntity.ok(Map.of(
                "history", history.stream().map(m -> Map.of(
                        "role", m.role(),
                        "content", m.content()
                )).toList(),
                "count", history.size()
        ));
    }

    /**
     * Clear conversation history for the current user.
     */
    @DeleteMapping("/history")
    public ResponseEntity<?> clearHistory(@AuthenticationPrincipal UserDetailsImpl userDetails) {
        aiChatService.clearHistory(userDetails.getUsername());
        return ResponseEntity.ok(Map.of("message", "Conversation history cleared"));
    }

    /**
     * Get available AI providers.
     */
    @GetMapping("/providers")
    public ResponseEntity<?> getProviders() {
        return ResponseEntity.ok(Map.of(
                "providers", List.of(
                        Map.of("id", "combined", "name", "Combined (All Models)", "description", "Merges HuggingFace AI with local NLP analysis for the best results", "free", true),
                        Map.of("id", "huggingface", "name", "HuggingFace AI", "description", "Free conversational AI models (DialoGPT, BlenderBot)", "free", true),
                        Map.of("id", "opennlp", "name", "Local NLP", "description", "OpenNLP-powered local analysis with knowledge base", "free", true)
                ),
                "default", "combined"
        ));
    }
}
