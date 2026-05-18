package com.example.aimoderation.service;

import com.example.aimoderation.config.AppModerationProperties;
import com.example.aimoderation.dto.CommentResponse;
import com.example.aimoderation.exception.ModerationRejectedException;
import com.example.aimoderation.exception.ResourceNotFoundException;
import com.example.aimoderation.model.AiSettings;
import com.example.aimoderation.model.Comment;
import com.example.aimoderation.model.CommentStatus;
import com.example.aimoderation.model.ImageModerationResult;
import com.example.aimoderation.model.ImageModerationStatus;
import com.example.aimoderation.model.ModerationTrainingData;
import com.example.aimoderation.model.Sentiment;
import com.example.aimoderation.model.User;
import com.example.aimoderation.repository.AiSettingsRepository;
import com.example.aimoderation.repository.CommentRepository;
import com.example.aimoderation.repository.ModerationTrainingDataRepository;
import com.example.aimoderation.repository.UserRepository;
import com.example.aimoderation.util.TextNormalizer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Base64;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class CommentService {

    private static final Logger logger = LoggerFactory.getLogger(CommentService.class);
    private static final int MAX_TRAINING_TOKENS = 12;
    private static final long MAX_COMMENT_IMAGE_BYTES = 4L * 1024 * 1024;

    @Autowired
    private CommentRepository commentRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private AiSettingsRepository aiSettingsRepository;

    @Autowired
    private SentimentAnalysisService sentimentAnalysisService;

    @Autowired
    private ModerationDecisionService moderationDecisionService;

    @Autowired
    private ModerationTrainingDataRepository trainingDataRepository;

    @Autowired
    private AppModerationProperties appProperties;

    @Autowired
    private ImageModerationService imageModerationService;

    @Transactional
    public CommentResponse createComment(String content, String username) {
        return createComment(content, username, null, null, null);
    }

    @Transactional
    public CommentResponse createComment(
            String content,
            String username,
            byte[] imageBytes,
            String filename,
            String contentType) {
        boolean hasImage = imageBytes != null && imageBytes.length > 0;
        String text = content != null ? content.trim() : "";
        validateContent(text, hasImage);

        User author = userRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        String imageDataUrl = null;
        if (hasImage) {
            if (imageBytes.length > MAX_COMMENT_IMAGE_BYTES) {
                throw new IllegalArgumentException("Image exceeds maximum size of 4 MB.");
            }
            String safeName = filename != null && !filename.isBlank() ? filename : "upload.jpg";
            String mime = contentType != null && !contentType.isBlank() ? contentType : "image/jpeg";
            ImageModerationResult imageResult = imageModerationService.moderateImage(
                    imageBytes, safeName, mime, author);
            if (imageResult.getStatus() != ImageModerationStatus.SAFE) {
                String reason = imageResult.getModerationReason() != null
                        ? imageResult.getModerationReason()
                        : "Image flagged as " + imageResult.getStatus().name();
                throw new ModerationRejectedException(
                        reason, "image", imageResult.getStatus().name());
            }
            imageDataUrl = "data:" + mime + ";base64,"
                    + Base64.getEncoder().encodeToString(imageBytes);
        }

        AiSettings settings = aiSettingsRepository.findFirstByOrderByIdAsc().orElse(null);

        SentimentAnalysisService.AnalysisResult analysis;
        if (text.isEmpty()) {
            analysis = new SentimentAnalysisService.AnalysisResult(
                    Sentiment.POSITIVE, 0.9, "Image-only message.", false, false);
        } else {
            analysis = sentimentAnalysisService.analyze(text);
        }
        ModerationDecisionService.ModerationDecision decision =
                moderationDecisionService.decide(analysis, settings);

        Comment comment = new Comment();
        comment.setContent(text);
        comment.setImageUrl(imageDataUrl);
        comment.setAuthor(author);
        comment.setSentiment(decision.sentiment());
        comment.setConfidenceScore(decision.confidence());
        comment.setStatus(decision.status());

        Comment saved = commentRepository.save(comment);
        logger.info("Comment moderation: status={}, sentiment={}, confidence={}, reason={}, hasImage={}",
                decision.status(), decision.sentiment(), decision.confidence(), decision.reason(), hasImage);

        return CommentResponse.from(saved, decision.reason());
    }

    @Transactional
    public void deleteComment(Long commentId) {
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new ResourceNotFoundException("Comment not found"));
        commentRepository.delete(comment);
        logger.info("Deleted comment id={} status={}", commentId, comment.getStatus());
    }

    public List<CommentResponse> getApprovedCommentsForAdmin() {
        return commentRepository.findByStatus(CommentStatus.APPROVED).stream()
                .sorted(Comparator.comparing(Comment::getCreatedAt,
                        Comparator.nullsLast(Comparator.naturalOrder())))
                .map(CommentResponse::from)
                .collect(Collectors.toList());
    }

    public List<CommentResponse> getAllApprovedComments() {
        return commentRepository.findByStatus(CommentStatus.APPROVED).stream()
                .sorted(Comparator.comparing(Comment::getCreatedAt,
                        Comparator.nullsLast(Comparator.naturalOrder())))
                .map(CommentResponse::from)
                .collect(Collectors.toList());
    }

    public List<CommentResponse> getPendingComments() {
        return commentRepository.findByStatus(CommentStatus.PENDING).stream()
                .sorted(Comparator.comparing(Comment::getCreatedAt,
                        Comparator.nullsLast(Comparator.reverseOrder())))
                .map(CommentResponse::from)
                .collect(Collectors.toList());
    }

    public ModerationDecisionService.ModerationDecision previewDecision(String content) {
        validateContent(content != null ? content : "", false);
        AiSettings settings = aiSettingsRepository.findFirstByOrderByIdAsc().orElse(null);
        SentimentAnalysisService.AnalysisResult analysis = sentimentAnalysisService.analyze(content);
        return moderationDecisionService.decide(analysis, settings);
    }

    @Transactional
    public CommentResponse moderateComment(Long commentId, boolean approved) {
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new ResourceNotFoundException("Comment not found"));

        CommentStatus newStatus = approved ? CommentStatus.APPROVED : CommentStatus.REJECTED;
        if (comment.getStatus() != newStatus) {
            comment.setStatus(newStatus);
            storeTrainingTokens(comment.getContent(), approved ? "POSITIVE" : "NEGATIVE");
            sentimentAnalysisService.invalidateLearnedCache();
        }

        return CommentResponse.from(commentRepository.save(comment));
    }

    private void validateContent(String content, boolean hasImage) {
        if ((content == null || content.trim().isEmpty()) && !hasImage) {
            throw new IllegalArgumentException("Message must include text or an image.");
        }
        if (content != null && !content.isEmpty()) {
            int maxLen = appProperties.getContent().getMaxCommentLength();
            if (content.length() > maxLen) {
                throw new IllegalArgumentException(
                        "Comment exceeds maximum length of " + maxLen + " characters.");
            }
        }
    }

    private void storeTrainingTokens(String content, String label) {
        String normalized = TextNormalizer.normalize(content);
        String[] words = normalized.split("\\s+");
        int stored = 0;
        for (String word : words) {
            if (word.length() >= 4 && word.length() <= 48) {
                ModerationTrainingData data = new ModerationTrainingData();
                data.setContent(word);
                data.setLabel(label);
                trainingDataRepository.save(data);
                stored++;
                if (stored >= MAX_TRAINING_TOKENS) {
                    break;
                }
            }
        }
        if (stored == 0 && normalized.length() >= 4) {
            ModerationTrainingData data = new ModerationTrainingData();
            data.setContent(normalized.substring(0, Math.min(48, normalized.length())));
            data.setLabel(label);
            trainingDataRepository.save(data);
        }
    }
}
