package com.example.aimoderation.controller;

import com.example.aimoderation.model.ImageModerationResult;
import com.example.aimoderation.model.ImageModerationStatus;
import com.example.aimoderation.model.User;
import com.example.aimoderation.repository.ImageModerationRepository;
import com.example.aimoderation.repository.UserRepository;
import com.example.aimoderation.service.ImageModerationService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * REST controller for image moderation operations.
 */
@RestController
@RequestMapping("/api/moderation/images")
@CrossOrigin(origins = "*")
public class ImageModerationController {

    @Autowired
    private ImageModerationService imageModerationService;

    @Autowired
    private ImageModerationRepository imageModerationRepository;

    @Autowired
    private UserRepository userRepository;

    /**
     * Upload and moderate an image.
     */
    @PostMapping("/upload")
    public ResponseEntity<ImageModerationResult> uploadImage(
            @RequestParam("file") MultipartFile file,
            Authentication authentication) {
        
        User user = null;
        if (authentication != null) {
            user = userRepository.findByUsername(authentication.getName()).orElse(null);
        }
        
        ImageModerationResult result = imageModerationService.moderateImage(file, user);
        
        if (result.getStatus() == ImageModerationStatus.ERROR) {
            return ResponseEntity.badRequest().body(result);
        }
        
        return ResponseEntity.ok(result);
    }

    /**
     * Get moderation result by ID.
     */
    @GetMapping("/{id}")
    public ResponseEntity<ImageModerationResult> getResult(@PathVariable Long id) {
        return imageModerationRepository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get all flagged images for review.
     */
    @GetMapping("/flagged")
    public ResponseEntity<List<ImageModerationResult>> getFlaggedImages() {
        List<ImageModerationResult> flagged = imageModerationRepository.findFlaggedForReview();
        return ResponseEntity.ok(flagged);
    }

    /**
     * Get images by status.
     */
    @GetMapping("/status/{status}")
    public ResponseEntity<List<ImageModerationResult>> getByStatus(@PathVariable ImageModerationStatus status) {
        List<ImageModerationResult> results = imageModerationRepository.findByStatus(status);
        return ResponseEntity.ok(results);
    }

    /**
     * Update moderation status (for manual review).
     */
    @PutMapping("/{id}/status")
    public ResponseEntity<ImageModerationResult> updateStatus(
            @PathVariable Long id,
            @RequestParam ImageModerationStatus status,
            @RequestParam(required = false) String reason) {
        
        return imageModerationRepository.findById(id)
                .map(result -> {
                    result.setStatus(status);
                    if (reason != null) {
                        result.setModerationReason(reason);
                    }
                    return ResponseEntity.ok(imageModerationRepository.save(result));
                })
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get moderation statistics.
     */
    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> getStats() {
        Map<String, Object> response = new HashMap<>();
        response.put("statusCounts", imageModerationService.getStats());
        response.put("totalImages", imageModerationRepository.count());
        return ResponseEntity.ok(response);
    }

    /**
     * Delete a moderation result.
     */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteResult(@PathVariable Long id) {
        if (imageModerationRepository.existsById(id)) {
            imageModerationRepository.deleteById(id);
            return ResponseEntity.ok().build();
        }
        return ResponseEntity.notFound().build();
    }
}
