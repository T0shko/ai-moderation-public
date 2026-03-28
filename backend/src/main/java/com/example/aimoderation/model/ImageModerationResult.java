package com.example.aimoderation.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * Entity for tracking image moderation results.
 */
@Entity
@Table(name = "image_moderation_result")
public class ImageModerationResult {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(nullable = false)
    private String imageUrl;
    
    @Column(name = "image_hash")
    private String imageHash;
    
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ImageModerationStatus status;
    
    @Column(name = "confidence_score")
    private Double confidenceScore;
    
    @Column(name = "detected_categories", columnDefinition = "TEXT")
    private String detectedCategories;
    
    @Column(name = "moderation_reason")
    private String moderationReason;
    
    @ManyToOne
    @JoinColumn(name = "user_id")
    private User uploadedBy;
    
    @Column(name = "created_at")
    private LocalDateTime createdAt;
    
    @Column(name = "moderated_at")
    private LocalDateTime moderatedAt;
    
    public ImageModerationResult() {}
    
    public ImageModerationResult(String imageUrl, ImageModerationStatus status) {
        this.imageUrl = imageUrl;
        this.status = status;
    }
    
    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getImageUrl() {
        return imageUrl;
    }

    public void setImageUrl(String imageUrl) {
        this.imageUrl = imageUrl;
    }

    public String getImageHash() {
        return imageHash;
    }

    public void setImageHash(String imageHash) {
        this.imageHash = imageHash;
    }

    public ImageModerationStatus getStatus() {
        return status;
    }

    public void setStatus(ImageModerationStatus status) {
        this.status = status;
    }

    public Double getConfidenceScore() {
        return confidenceScore;
    }

    public void setConfidenceScore(Double confidenceScore) {
        this.confidenceScore = confidenceScore;
    }

    public String getDetectedCategories() {
        return detectedCategories;
    }

    public void setDetectedCategories(String detectedCategories) {
        this.detectedCategories = detectedCategories;
    }

    public String getModerationReason() {
        return moderationReason;
    }

    public void setModerationReason(String moderationReason) {
        this.moderationReason = moderationReason;
    }

    public User getUploadedBy() {
        return uploadedBy;
    }

    public void setUploadedBy(User uploadedBy) {
        this.uploadedBy = uploadedBy;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getModeratedAt() {
        return moderatedAt;
    }

    public void setModeratedAt(LocalDateTime moderatedAt) {
        this.moderatedAt = moderatedAt;
    }
}
