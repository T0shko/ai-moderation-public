package com.example.aimoderation.exception;

public class ModerationRejectedException extends RuntimeException {

    private final String moderationType;
    private final String status;

    public ModerationRejectedException(String message, String moderationType, String status) {
        super(message);
        this.moderationType = moderationType;
        this.status = status;
    }

    public String getModerationType() {
        return moderationType;
    }

    public String getStatus() {
        return status;
    }
}
