package com.example.aimoderation.controller;

import com.example.aimoderation.payload.response.ErrorResponse;
import com.example.aimoderation.payload.response.ErrorResponse.FieldError;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.authentication.LockedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.support.MissingServletRequestPartException;
import org.springframework.web.servlet.NoHandlerFoundException;

import java.util.List;

/**
 * Catches all unhandled exceptions and returns the {@link ErrorResponse} JSON
 * envelope. Never leaks raw stack traces or internal exception messages to
 * clients — those go to the logs only.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger logger = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    // ── Validation ─────────────────────────────────────────────────

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(
            MethodArgumentNotValidException e, HttpServletRequest req) {
        List<FieldError> fields = e.getBindingResult().getFieldErrors().stream()
                .map(fe -> new FieldError(fe.getField(),
                        fe.getDefaultMessage() != null ? fe.getDefaultMessage() : "invalid"))
                .toList();
        ErrorResponse body = ErrorResponse.of(
                "validation_failed",
                "Request payload failed validation.",
                HttpStatus.BAD_REQUEST.value(), req.getRequestURI())
                .withFieldErrors(fields);
        return ResponseEntity.badRequest().body(body);
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ErrorResponse> handleConstraintViolation(
            ConstraintViolationException e, HttpServletRequest req) {
        List<FieldError> fields = e.getConstraintViolations().stream()
                .map(cv -> new FieldError(cv.getPropertyPath().toString(), cv.getMessage()))
                .toList();
        ErrorResponse body = ErrorResponse.of(
                "validation_failed",
                "Request failed validation.",
                HttpStatus.BAD_REQUEST.value(), req.getRequestURI())
                .withFieldErrors(fields);
        return ResponseEntity.badRequest().body(body);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ErrorResponse> handleUnreadable(
            HttpMessageNotReadableException e, HttpServletRequest req) {
        return ResponseEntity.badRequest().body(ErrorResponse.of(
                "malformed_request_body",
                "Request body is missing or malformed JSON.",
                HttpStatus.BAD_REQUEST.value(), req.getRequestURI()));
    }

    // ── Auth / authz ───────────────────────────────────────────────

    @ExceptionHandler(BadCredentialsException.class)
    public ResponseEntity<ErrorResponse> handleBadCredentials(
            BadCredentialsException e, HttpServletRequest req) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(ErrorResponse.of(
                "invalid_credentials",
                "Username or password is incorrect.",
                HttpStatus.UNAUTHORIZED.value(), req.getRequestURI()));
    }

    @ExceptionHandler(LockedException.class)
    public ResponseEntity<ErrorResponse> handleLocked(LockedException e, HttpServletRequest req) {
        return ResponseEntity.status(HttpStatus.LOCKED).body(ErrorResponse.of(
                "account_locked",
                e.getMessage() != null ? e.getMessage() : "Account is temporarily locked.",
                HttpStatus.LOCKED.value(), req.getRequestURI()));
    }

    @ExceptionHandler(DisabledException.class)
    public ResponseEntity<ErrorResponse> handleDisabled(DisabledException e, HttpServletRequest req) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(ErrorResponse.of(
                "account_disabled",
                "This account has been disabled.",
                HttpStatus.FORBIDDEN.value(), req.getRequestURI()));
    }

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<ErrorResponse> handleAuth(AuthenticationException e, HttpServletRequest req) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(ErrorResponse.of(
                "unauthenticated",
                "Authentication failed.",
                HttpStatus.UNAUTHORIZED.value(), req.getRequestURI()));
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ErrorResponse> handleAccessDenied(
            AccessDeniedException e, HttpServletRequest req) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(ErrorResponse.of(
                "forbidden",
                "You do not have permission to perform this action.",
                HttpStatus.FORBIDDEN.value(), req.getRequestURI()));
    }

    // ── HTTP-level ─────────────────────────────────────────────────

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<ErrorResponse> handleMaxUploadSize(
            MaxUploadSizeExceededException e, HttpServletRequest req) {
        logger.warn("Upload too large: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE).body(ErrorResponse.of(
                "payload_too_large",
                "File is too large. Maximum size is 10 MB.",
                HttpStatus.PAYLOAD_TOO_LARGE.value(), req.getRequestURI()));
    }

    @ExceptionHandler(MissingServletRequestPartException.class)
    public ResponseEntity<ErrorResponse> handleMissingPart(
            MissingServletRequestPartException e, HttpServletRequest req) {
        return ResponseEntity.badRequest().body(ErrorResponse.of(
                "missing_file_part",
                "No file provided. Send a multipart request with a 'file' field.",
                HttpStatus.BAD_REQUEST.value(), req.getRequestURI()));
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ErrorResponse> handleMethodNotSupported(
            HttpRequestMethodNotSupportedException e, HttpServletRequest req) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).body(ErrorResponse.of(
                "method_not_allowed",
                "Method not allowed for this resource.",
                HttpStatus.METHOD_NOT_ALLOWED.value(), req.getRequestURI()));
    }

    @ExceptionHandler(NoHandlerFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(
            NoHandlerFoundException e, HttpServletRequest req) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(ErrorResponse.of(
                "not_found",
                "Resource not found.",
                HttpStatus.NOT_FOUND.value(), req.getRequestURI()));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorResponse> handleIllegalArgument(
            IllegalArgumentException e, HttpServletRequest req) {
        return ResponseEntity.badRequest().body(ErrorResponse.of(
                "bad_request",
                e.getMessage() != null ? e.getMessage() : "Bad request.",
                HttpStatus.BAD_REQUEST.value(), req.getRequestURI()));
    }

    // ── Catch-all ──────────────────────────────────────────────────

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneral(Exception e, HttpServletRequest req) {
        logger.error("Unhandled exception on {}: {}", req.getRequestURI(), e.getMessage(), e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ErrorResponse.of(
                "internal_error",
                "An unexpected error occurred. Please try again later.",
                HttpStatus.INTERNAL_SERVER_ERROR.value(), req.getRequestURI()));
    }
}
