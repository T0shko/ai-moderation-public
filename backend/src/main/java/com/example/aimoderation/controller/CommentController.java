package com.example.aimoderation.controller;

import com.example.aimoderation.dto.CommentResponse;
import com.example.aimoderation.service.CommentService;
import com.example.aimoderation.service.ModerationDecisionService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/comments")
public class CommentController {

    @Autowired
    private CommentService commentService;

    @GetMapping
    public List<CommentResponse> getAllApprovedComments() {
        return commentService.getAllApprovedComments();
    }

    @PostMapping
    @PreAuthorize("hasRole('USER') or hasRole('MODERATOR') or hasRole('ADMIN')")
    public ResponseEntity<CommentResponse> postComment(@RequestBody CommentRequest request) {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        CommentResponse comment = commentService.createComment(request.getContent(), username);
        return ResponseEntity.ok(comment);
    }

    @GetMapping("/pending")
    @PreAuthorize("hasRole('MODERATOR') or hasRole('ADMIN')")
    public List<CommentResponse> getPendingComments() {
        return commentService.getPendingComments();
    }

    @PostMapping("/{id}/moderate")
    @PreAuthorize("hasRole('MODERATOR') or hasRole('ADMIN')")
    public ResponseEntity<CommentResponse> moderateComment(
            @PathVariable Long id, @RequestParam boolean approved) {
        return ResponseEntity.ok(commentService.moderateComment(id, approved));
    }

    @PostMapping("/test-analyze")
    @PreAuthorize("hasRole('MODERATOR') or hasRole('ADMIN')")
    public ResponseEntity<Map<String, Object>> testAnalyze(
            @RequestBody(required = false) CommentRequest request) {

        String content = (request != null && request.getContent() != null)
                ? request.getContent()
                : "";

        ModerationDecisionService.ModerationDecision decision;
        if (content.isBlank()) {
            decision = new ModerationDecisionService.ModerationDecision(
                    com.example.aimoderation.model.CommentStatus.PENDING,
                    false,
                    "Empty content.",
                    com.example.aimoderation.model.Sentiment.NEUTRAL,
                    0.5);
        } else {
            decision = commentService.previewDecision(content);
        }

        Map<String, Object> response = new HashMap<>();
        response.put("content", content);
        response.put("sentiment", decision.sentiment().name());
        response.put("confidence", decision.confidence());
        response.put("status", decision.status().name());
        response.put("reason", decision.reason());
        response.put("wouldBeAutoApproved", decision.wouldBeAutoApproved());
        return ResponseEntity.ok(response);
    }

    public static class CommentRequest {
        private String content;

        public String getContent() {
            return content;
        }

        public void setContent(String content) {
            this.content = content;
        }
    }
}
