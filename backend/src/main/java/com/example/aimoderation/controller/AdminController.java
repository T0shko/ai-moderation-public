package com.example.aimoderation.controller;

import com.example.aimoderation.model.Comment;
import com.example.aimoderation.model.Role;
import com.example.aimoderation.model.User;
import com.example.aimoderation.model.AiSettings;
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

@CrossOrigin(origins = "*", maxAge = 3600)
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

    @GetMapping("/comments")
    public ResponseEntity<List<Comment>> getAllComments() {
        return ResponseEntity.ok(commentRepository.findAll());
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
                .orElseThrow(() -> new RuntimeException("Error: User not found."));

        user.setRole(role);
        userRepository.save(user);

        return ResponseEntity.ok("User role updated successfully!");
    }

    @GetMapping("/ai-settings")
    public ResponseEntity<?> getAiSettings() {
        return ResponseEntity.ok(aiSettingsRepository.findFirstByOrderByIdAsc()
                .orElseThrow(() -> new RuntimeException("AI Settings not found")));
    }

    @PostMapping("/ai-settings")
    public ResponseEntity<?> updateAiSettings(@RequestBody AiSettings settings) {
        AiSettings current = aiSettingsRepository.findFirstByOrderByIdAsc()
                .orElse(new AiSettings());

        current.setThreshold(settings.getThreshold());
        current.setActiveModel(settings.getActiveModel());
        aiSettingsRepository.save(current);

        return ResponseEntity.ok("AI Settings updated successfully!");
    }
}
