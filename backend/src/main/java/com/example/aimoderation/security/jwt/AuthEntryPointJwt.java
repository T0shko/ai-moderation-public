package com.example.aimoderation.security.jwt;

import java.io.IOException;

import com.example.aimoderation.payload.response.ErrorResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;

/**
 * Translates Spring Security AuthenticationExceptions into our structured
 * ErrorResponse JSON, and surfaces the precise reason set by AuthTokenFilter
 * so clients can decide whether to attempt a refresh.
 */
@Component
public class AuthEntryPointJwt implements AuthenticationEntryPoint {

    private static final Logger logger = LoggerFactory.getLogger(AuthEntryPointJwt.class);

    @Autowired
    private ObjectMapper objectMapper;

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response,
            AuthenticationException authException) throws IOException, ServletException {

        String reason = (String) request.getAttribute(AuthTokenFilter.REASON_REQUEST_ATTR);
        String code;
        String message;

        if (reason == null) {
            code = "unauthenticated";
            message = "Authentication is required to access this resource.";
        } else {
            code = reason;
            message = switch (reason) {
                case "token_expired" -> "Access token has expired. Refresh it and retry.";
                case "invalid_signature" -> "Token signature is invalid.";
                case "malformed_token" -> "Token is malformed.";
                case "unsupported_token" -> "Token type is not supported.";
                case "empty_token" -> "No authentication token was provided.";
                default -> "Authentication failed.";
            };
        }

        logger.debug("Unauthenticated request to {} (reason={})", request.getRequestURI(), code);

        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        if ("token_expired".equals(code)) {
            response.setHeader("WWW-Authenticate",
                    "Bearer error=\"invalid_token\", error_description=\"token_expired\"");
        }

        ErrorResponse body = ErrorResponse.of(
                code, message,
                HttpServletResponse.SC_UNAUTHORIZED,
                request.getRequestURI());
        objectMapper.writeValue(response.getOutputStream(), body);
    }
}
