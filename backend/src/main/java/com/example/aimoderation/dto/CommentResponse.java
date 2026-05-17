package com.example.aimoderation.dto;

import com.example.aimoderation.model.Comment;
import com.example.aimoderation.model.CommentStatus;
import com.example.aimoderation.model.Sentiment;
import com.example.aimoderation.model.User;

import java.time.LocalDateTime;

public class CommentResponse {
    private Long id;
    private String content;
    private UserPublicDto author;
    private String sentiment;
    private Double confidenceScore;
    private String status;
    private String moderationReason;
    private LocalDateTime createdAt;

    public static CommentResponse from(Comment comment) {
        return from(comment, null);
    }

    public static CommentResponse from(Comment comment, String moderationReason) {
        CommentResponse dto = new CommentResponse();
        dto.id = comment.getId();
        dto.content = comment.getContent();
        dto.author = comment.getAuthor() != null ? UserPublicDto.from(comment.getAuthor()) : null;
        dto.sentiment = comment.getSentiment() != null ? comment.getSentiment().name() : null;
        dto.confidenceScore = comment.getConfidenceScore();
        dto.status = comment.getStatus() != null ? comment.getStatus().name() : null;
        dto.moderationReason = moderationReason;
        dto.createdAt = comment.getCreatedAt();
        return dto;
    }

    public Long getId() { return id; }
    public String getContent() { return content; }
    public UserPublicDto getAuthor() { return author; }
    public String getSentiment() { return sentiment; }
    public Double getConfidenceScore() { return confidenceScore; }
    public String getStatus() { return status; }
    public String getModerationReason() { return moderationReason; }
    public LocalDateTime getCreatedAt() { return createdAt; }
}
