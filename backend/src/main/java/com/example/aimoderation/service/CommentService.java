package com.example.aimoderation.service;

import com.example.aimoderation.config.AppModerationProperties;
import com.example.aimoderation.dto.CommentResponse;
import com.example.aimoderation.exception.ResourceNotFoundException;
import com.example.aimoderation.model.AiSettings;
import com.example.aimoderation.model.Comment;
import com.example.aimoderation.model.CommentStatus;
import com.example.aimoderation.model.ModerationTrainingData;
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

import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class CommentService {

    private static final Logger logger = LoggerFactory.getLogger(CommentService.class);
    private static final int MAX_TRAINING_TOKENS = 12;

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

    @Transactional
    public CommentResponse createComment(String content, String username) {
        validateContent(content);

        User author = userRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        AiSettings settings = aiSettingsRepository.findFirstByOrderByIdAsc().orElse(null);

        SentimentAnalysisService.AnalysisResult analysis = sentimentAnalysisService.analyze(content);
        ModerationDecisionService.ModerationDecision decision =
                moderationDecisionService.decide(analysis, settings);

        Comment comment = new Comment();
        comment.setContent(content.trim());
        comment.setAuthor(author);
        comment.setSentiment(decision.sentiment());
        comment.setConfidenceScore(decision.confidence());
        comment.setStatus(decision.status());

        Comment saved = commentRepository.save(comment);
        logger.info("Comment moderation: status={}, sentiment={}, confidence={}, reason={}",
                decision.status(), decision.sentiment(), decision.confidence(), decision.reason());

        return CommentResponse.from(saved, decision.reason());
    }

    public List<CommentResponse> getAllApprovedComments() {
        return commentRepository.findByStatus(CommentStatus.APPROVED).stream()
                .sorted(Comparator.comparing(Comment::getCreatedAt,
                        Comparator.nullsLast(Comparator.reverseOrder())))
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
        validateContent(content);
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

    private void validateContent(String content) {
        if (content == null || content.trim().isEmpty()) {
            throw new IllegalArgumentException("Comment content cannot be empty.");
        }
        int maxLen = appProperties.getContent().getMaxCommentLength();
        if (content.length() > maxLen) {
            throw new IllegalArgumentException(
                    "Comment exceeds maximum length of " + maxLen + " characters.");
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
