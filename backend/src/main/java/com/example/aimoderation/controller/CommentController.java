package com.example.aimoderation.controller;

import com.example.aimoderation.model.Comment;
import com.example.aimoderation.service.CommentService;
import com.example.aimoderation.service.SentimentAnalysisService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@CrossOrigin(origins = "*", maxAge = 3600)
@RestController
@RequestMapping("/api/comments")
public class CommentController {

    @Autowired
    private CommentService commentService;

    @Autowired
    private SentimentAnalysisService sentimentAnalysisService;

    @GetMapping
    public List<Comment> getAllApprovedComments() {
        return commentService.getAllApprovedComments();
    }

    @PostMapping
    @PreAuthorize("hasRole('USER') or hasRole('MODERATOR') or hasRole('ADMIN')")
    public ResponseEntity<Comment> postComment(@RequestBody CommentRequest request) {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Comment comment = commentService.createComment(request.getContent(), username);
        return ResponseEntity.ok(comment);
    }

    @GetMapping("/pending")
    @PreAuthorize("hasRole('MODERATOR') or hasRole('ADMIN')")
    public List<Comment> getPendingComments() {
        return commentService.getPendingComments();
    }

    @PostMapping("/{id}/moderate")
    @PreAuthorize("hasRole('MODERATOR') or hasRole('ADMIN')")
    public ResponseEntity<Comment> moderateComment(@PathVariable Long id, @RequestParam boolean approved) {
        Comment comment = commentService.moderateComment(id, approved);
        return ResponseEntity.ok(comment);
    }

    /**
     * Test endpoint for analyzing text sentiment without creating a comment.
     * This is useful for the admin panel testing console.
     */
    @PostMapping("/test-analyze")
    @PreAuthorize("hasRole('MODERATOR') or hasRole('ADMIN')")
    public ResponseEntity<Map<String, Object>> testAnalyze(@RequestBody CommentRequest request) {
        SentimentAnalysisService.AnalysisResult result = sentimentAnalysisService.analyze(request.getContent());
        
        Map<String, Object> response = new HashMap<>();
        response.put("content", request.getContent());
        response.put("sentiment", result.getSentiment().name());
        response.put("confidence", result.getConfidence());
        response.put("wouldBeAutoApproved", result.getSentiment().name().equals("POSITIVE") || 
                                            result.getSentiment().name().equals("NEUTRAL"));
        
        return ResponseEntity.ok(response);
    }

    // Simple DTO for request
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

