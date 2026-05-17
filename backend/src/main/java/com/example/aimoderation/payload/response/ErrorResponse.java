package com.example.aimoderation.payload.response;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.Instant;
import java.util.List;

/**
 * Uniform error envelope returned by the API.
 *
 * Shape:
 * {
 *   "code":    "invalid_credentials",
 *   "message": "Username or password is incorrect.",
 *   "status":  401,
 *   "path":    "/api/auth/signin",
 *   "timestamp": "2026-05-12T11:50:21Z",
 *   "errors":  [ { "field": "password", "message": "must not be blank" } ]   // optional
 * }
 */
@JsonInclude(JsonInclude.Include.NON_EMPTY)
public class ErrorResponse {
    private String code;
    private String message;
    private int status;
    private String path;
    private Instant timestamp;
    private List<FieldError> errors;

    public ErrorResponse() {}

    public ErrorResponse(String code, String message, int status, String path) {
        this.code = code;
        this.message = message;
        this.status = status;
        this.path = path;
        this.timestamp = Instant.now();
    }

    public static ErrorResponse of(String code, String message, int status, String path) {
        return new ErrorResponse(code, message, status, path);
    }

    public ErrorResponse withFieldErrors(List<FieldError> errors) {
        this.errors = errors;
        return this;
    }

    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }
    public String getMessage() { return message; }
    public void setMessage(String message) { this.message = message; }
    public int getStatus() { return status; }
    public void setStatus(int status) { this.status = status; }
    public String getPath() { return path; }
    public void setPath(String path) { this.path = path; }
    public Instant getTimestamp() { return timestamp; }
    public void setTimestamp(Instant timestamp) { this.timestamp = timestamp; }
    public List<FieldError> getErrors() { return errors; }
    public void setErrors(List<FieldError> errors) { this.errors = errors; }

    public record FieldError(String field, String message) {}
}
