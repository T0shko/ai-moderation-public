package com.example.aimoderation.controller;

import com.example.aimoderation.dto.CommentResponse;
import com.example.aimoderation.exception.ResourceNotFoundException;
import com.example.aimoderation.model.Role;
import com.example.aimoderation.model.User;
import com.example.aimoderation.model.AiSettings;
import com.example.aimoderation.service.CommentService;
import com.example.aimoderation.service.HuggingFaceIntegrationService;
import com.example.aimoderation.service.ImageModerationService;
import com.example.aimoderation.repository.UserRepository;
import com.example.aimoderation.repository.CommentRepository;
import com.example.aimoderation.repository.AiSettingsRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/admin")
@PreAuthorize("hasRole('ADMIN')")
public class AdminController {

    @Autowired
    UserRepository userRepository;

    @Autowired
    AiSettingsRepository aiSettingsRepository;

    @Autowired
    CommentRepository commentRepository;

    @Autowired
    CommentService commentService;

    @Autowired
    ImageModerationService imageModerationService;

    @Autowired
    HuggingFaceIntegrationService huggingFaceIntegrationService;

    @GetMapping("/integrations/huggingface")
    public ResponseEntity<Map<String, Object>> getHuggingFaceStatus() {
        return ResponseEntity.ok(huggingFaceIntegrationService.getStatus());
    }

    @DeleteMapping("/image-moderation")
    public ResponseEntity<Map<String, Object>> clearImageModerationHistory() {
        long removed = imageModerationService.clearAllResults();
        return ResponseEntity.ok(Map.of(
                "message", "Image moderation history cleared.",
                "removed", removed));
    }

    @GetMapping("/comments")
    public ResponseEntity<List<CommentResponse>> getAllComments() {
        return ResponseEntity.ok(commentRepository.findAll().stream()
                .map(CommentResponse::from)
                .collect(Collectors.toList()));
    }

    @GetMapping("/comments/approved")
    public ResponseEntity<List<CommentResponse>> getApprovedComments() {
        return ResponseEntity.ok(commentService.getApprovedCommentsForAdmin());
    }

    @DeleteMapping("/comments/{id}")
    public ResponseEntity<Map<String, String>> deleteComment(@PathVariable Long id) {
        commentService.deleteComment(id);
        return ResponseEntity.ok(Map.of("message", "Comment removed from public feed."));
    }

    @GetMapping("/users")
    public List<Map<String, Object>> getAllUsers() {
        return (List<Map<String, Object>>) (Object) userRepository.findAll().stream()
                .map(user -> Map.of(
                        "id", user.getId(),
                        "username", user.getUsername(),
                        "role", user.getRole().toString()))
                .collect(Collectors.toList());
    }

    @PostMapping("/users/{id}/role")
    public ResponseEntity<?> updateUserRole(@PathVariable Long id, @RequestParam Role role) {
        User user = userRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("User not found."));

        user.setRole(role);
        userRepository.save(user);

        return ResponseEntity.ok("User role updated successfully!");
    }

    @GetMapping("/ai-settings")
    public ResponseEntity<?> getAiSettings() {
        return ResponseEntity.ok(aiSettingsRepository.findFirstByOrderByIdAsc()
                .orElseThrow(() -> new ResourceNotFoundException("AI Settings not found")));
    }

    @PostMapping("/ai-settings")
    public ResponseEntity<?> updateAiSettings(@RequestBody AiSettings settings) {
        if (settings.getThreshold() == null || settings.getThreshold() < 0 || settings.getThreshold() > 1) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Threshold must be between 0.0 and 1.0"));
        }
        String model = settings.getActiveModel();
        if (model == null || model.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "activeModel is required"));
        }

        AiSettings current = aiSettingsRepository.findFirstByOrderByIdAsc()
                .orElse(new AiSettings());

        current.setThreshold(settings.getThreshold());
        current.setActiveModel(model.trim().toLowerCase());
        aiSettingsRepository.save(current);

        return ResponseEntity.ok(current);
    }
}
