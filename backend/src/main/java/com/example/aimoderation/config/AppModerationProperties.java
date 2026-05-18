package com.example.aimoderation.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
@ConfigurationProperties(prefix = "app.defaults")
public class AppModerationProperties {

    private final Moderation moderation = new Moderation();
    private final Content content = new Content();
    private final Chat chat = new Chat();

    public Moderation getModeration() {
        return moderation;
    }

    public Content getContent() {
        return content;
    }

    public Chat getChat() {
        return chat;
    }

    public static class Moderation {
        private double threshold = 0.7;
        private String activeModel = "wordfilter";
        private boolean autoApprovePositive = true;
        private boolean autoRejectHighConfidence = true;
        private double autoRejectThreshold = 0.85;

        public double getThreshold() { return threshold; }
        public void setThreshold(double threshold) { this.threshold = threshold; }
        public String getActiveModel() { return activeModel; }
        public void setActiveModel(String activeModel) { this.activeModel = activeModel; }
        public boolean isAutoApprovePositive() { return autoApprovePositive; }
        public void setAutoApprovePositive(boolean autoApprovePositive) { this.autoApprovePositive = autoApprovePositive; }
        public boolean isAutoRejectHighConfidence() { return autoRejectHighConfidence; }
        public void setAutoRejectHighConfidence(boolean autoRejectHighConfidence) { this.autoRejectHighConfidence = autoRejectHighConfidence; }
        public double getAutoRejectThreshold() { return autoRejectThreshold; }
        public void setAutoRejectThreshold(double autoRejectThreshold) { this.autoRejectThreshold = autoRejectThreshold; }
    }

    public static class Content {
        private int maxCommentLength = 1000;

        public int getMaxCommentLength() { return maxCommentLength; }
        public void setMaxCommentLength(int maxCommentLength) { this.maxCommentLength = maxCommentLength; }
    }

    public static class Chat {
        private int maxMessageLength = 2000;
        private int rateLimitPerMinute = 30;

        public int getMaxMessageLength() { return maxMessageLength; }
        public void setMaxMessageLength(int maxMessageLength) { this.maxMessageLength = maxMessageLength; }
        public int getRateLimitPerMinute() { return rateLimitPerMinute; }
        public void setRateLimitPerMinute(int rateLimitPerMinute) { this.rateLimitPerMinute = rateLimitPerMinute; }
    }
}
