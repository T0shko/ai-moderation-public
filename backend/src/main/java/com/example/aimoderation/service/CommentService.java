package com.example.aimoderation.service;

import com.example.aimoderation.model.AiSettings;
import com.example.aimoderation.model.Comment;
import com.example.aimoderation.model.CommentStatus;
import com.example.aimoderation.model.ModerationTrainingData;
import com.example.aimoderation.model.Sentiment;
import com.example.aimoderation.model.User;
import com.example.aimoderation.repository.AiSettingsRepository;
import com.example.aimoderation.repository.CommentRepository;
import com.example.aimoderation.repository.ModerationTrainingDataRepository;
import com.example.aimoderation.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class CommentService {

    private static final Logger logger = LoggerFactory.getLogger(CommentService.class);

    @Autowired
    private CommentRepository commentRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private AiSettingsRepository aiSettingsRepository;

    @Autowired
    private SentimentAnalysisService sentimentAnalysisService;

    @Autowired
    private ClaudeTextModerationService claudeTextModerationService;

    @Autowired
    private ModerationTrainingDataRepository trainingDataRepository;

    @Transactional
    public Comment createComment(String content, String username) {
        User author = userRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("User not found"));

        Comment comment = new Comment();
        comment.setContent(content);
        comment.setAuthor(author);

        AiSettings settings = aiSettingsRepository.findFirstByOrderByIdAsc().orElse(null);
        String activeModel = settings != null ? settings.getActiveModel() : "ensemble";
        double threshold = settings != null && settings.getThreshold() != null ? settings.getThreshold() : 0.7;

        // === ENSEMBLE MODERATION: Run all applicable models, block if ANY flags ===
        SentimentAnalysisService.AnalysisResult wordFilterResult = null;
        ClaudeTextModerationService.TextModerationResult claudeResult = null;

        boolean wordFilterBlocks = false;
        boolean claudeBlocks = false;

        // Run word-filter model (always fast, no API cost)
        if (!"claude-only".equals(activeModel)) {
            wordFilterResult = sentimentAnalysisService.analyze(content);
            wordFilterBlocks = wordFilterResult.getSentiment() == Sentiment.NEGATIVE;
            logger.info("Word-filter result: sentiment={}, confidence={}", wordFilterResult.getSentiment(), wordFilterResult.getConfidence());
        }

        // Run Claude AI model
        if (!"basic-v1".equals(activeModel)) {
            claudeResult = claudeTextModerationService.moderateText(content);
            claudeBlocks = claudeResult.blocked();
            logger.info("Claude result: blocked={}, confidence={}, categories={}", claudeResult.blocked(), claudeResult.confidence(), claudeResult.categories());
        }

        // Ensemble decision: if ANY model says block → PENDING for review
        boolean shouldBlock = wordFilterBlocks || claudeBlocks;

        // Use highest confidence across all models
        double maxConfidence = 0.0;
        Sentiment finalSentiment = Sentiment.NEUTRAL;
        if (wordFilterResult != null) {
            maxConfidence = Math.max(maxConfidence, wordFilterResult.getConfidence());
            finalSentiment = wordFilterResult.getSentiment();
        }
        if (claudeResult != null) {
            maxConfidence = Math.max(maxConfidence, claudeResult.confidence());
            if (claudeResult.blocked()) finalSentiment = Sentiment.NEGATIVE;
        }

        comment.setSentiment(finalSentiment);
        comment.setConfidenceScore(maxConfidence);

        // If below threshold, also flag for review (even if no model detected issues)
        if (shouldBlock || maxConfidence < threshold) {
            comment.setStatus(CommentStatus.PENDING);
        } else {
            comment.setStatus(CommentStatus.APPROVED);
        }

        logger.info("Comment moderation: shouldBlock={}, confidence={}, status={}", shouldBlock, maxConfidence, comment.getStatus());
        return commentRepository.save(comment);
    }

    public List<Comment> getAllApprovedComments() {
        return commentRepository.findByStatus(CommentStatus.APPROVED);
    }

    public List<Comment> getPendingComments() {
        return commentRepository.findByStatus(CommentStatus.PENDING);
    }

    @Transactional
    public Comment moderateComment(Long commentId, boolean approved) {
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new RuntimeException("Comment not found"));

        comment.setStatus(approved ? CommentStatus.APPROVED : CommentStatus.REJECTED);

        // Store for model training / learning
        ModerationTrainingData trainingData = new ModerationTrainingData();
        trainingData.setContent(comment.getContent());
        trainingData.setLabel(approved ? "POSITIVE" : "NEGATIVE");
        trainingDataRepository.save(trainingData);

        return commentRepository.save(comment);
    }
}
