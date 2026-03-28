package com.example.aimoderation.repository;

import com.example.aimoderation.model.ImageModerationResult;
import com.example.aimoderation.model.ImageModerationStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

/**
 * Repository for managing image moderation results.
 */
@Repository
public interface ImageModerationRepository extends JpaRepository<ImageModerationResult, Long> {
    
    /**
     * Find moderation result by image URL.
     */
    Optional<ImageModerationResult> findByImageUrl(String imageUrl);
    
    /**
     * Find moderation result by image hash (for duplicate detection).
     */
    Optional<ImageModerationResult> findByImageHash(String imageHash);
    
    /**
     * Find all results with a specific status.
     */
    List<ImageModerationResult> findByStatus(ImageModerationStatus status);
    
    /**
     * Find all results for a specific user.
     */
    List<ImageModerationResult> findByUploadedById(Long userId);
    
    /**
     * Find pending images for moderation.
     */
    List<ImageModerationResult> findByStatusOrderByCreatedAtAsc(ImageModerationStatus status);
    
    /**
     * Find flagged images for manual review.
     */
    @Query("SELECT i FROM ImageModerationResult i WHERE i.status = 'FLAGGED' ORDER BY i.createdAt DESC")
    List<ImageModerationResult> findFlaggedForReview();
    
    /**
     * Count images by status.
     */
    long countByStatus(ImageModerationStatus status);
    
    /**
     * Find images uploaded within a date range.
     */
    @Query("SELECT i FROM ImageModerationResult i WHERE i.createdAt BETWEEN :startDate AND :endDate")
    List<ImageModerationResult> findByDateRange(
            @Param("startDate") LocalDateTime startDate,
            @Param("endDate") LocalDateTime endDate);
    
    /**
     * Check if an image with the given hash has already been rejected.
     */
    @Query("SELECT CASE WHEN COUNT(i) > 0 THEN true ELSE false END FROM ImageModerationResult i " +
           "WHERE i.imageHash = :hash AND i.status = 'REJECTED'")
    boolean isHashRejected(@Param("hash") String hash);
}
