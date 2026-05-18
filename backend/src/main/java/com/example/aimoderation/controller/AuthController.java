package com.example.aimoderation.controller;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.stream.Collectors;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.authentication.LockedException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.example.aimoderation.model.RefreshToken;
import com.example.aimoderation.model.Role;
import com.example.aimoderation.model.User;
import com.example.aimoderation.payload.request.LoginRequest;
import com.example.aimoderation.payload.request.RefreshTokenRequest;
import com.example.aimoderation.payload.request.SignupRequest;
import com.example.aimoderation.payload.response.ErrorResponse;
import com.example.aimoderation.payload.response.JwtResponse;
import com.example.aimoderation.payload.response.MessageResponse;
import com.example.aimoderation.payload.response.UserProfileResponse;
import com.example.aimoderation.repository.UserRepository;
import com.example.aimoderation.security.jwt.JwtUtils;
import com.example.aimoderation.security.services.RefreshTokenService;
import com.example.aimoderation.security.services.UserDetailsImpl;

/**
 * Enterprise auth surface:
 *   POST /api/auth/signin   → access + refresh tokens (+ lockout)
 *   POST /api/auth/signup   → new account
 *   POST /api/auth/refresh  → rotate refresh, issue new access token
 *   POST /api/auth/logout   → revoke the supplied refresh token
 *   GET  /api/auth/me       → current user profile (validates session)
 *
 * NOTE: No @CrossOrigin here — CORS is centrally configured in WebSecurityConfig.
 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private static final Logger logger = LoggerFactory.getLogger(AuthController.class);

    @Autowired private AuthenticationManager authenticationManager;
    @Autowired private UserRepository userRepository;
    @Autowired private PasswordEncoder encoder;
    @Autowired private JwtUtils jwtUtils;
    @Autowired private RefreshTokenService refreshTokenService;

    @Value("${security.lockout.max-attempts:5}")
    private int maxFailedAttempts;

    @Value("${security.lockout.duration-minutes:15}")
    private int lockoutDurationMinutes;

    // ── Sign-in ────────────────────────────────────────────────────

    @PostMapping("/signin")
    @Transactional
    public ResponseEntity<?> authenticateUser(
            @Valid @RequestBody LoginRequest loginRequest,
            HttpServletRequest request) {

        String username = loginRequest.getUsername();

        // Pre-check: lockout window still active? Fail fast so we don't
        // even hit the password verifier (avoids both leak + side effects).
        var existingUserOpt = userRepository.findByUsername(username);
        if (existingUserOpt.isPresent()) {
            User existing = existingUserOpt.get();
            if (existing.isLocked()) {
                long secondsLeft = Math.max(0,
                        Duration.between(Instant.now(), existing.getLockedUntil()).getSeconds());
                logger.warn("Login attempt on locked account '{}', {}s remaining", username, secondsLeft);
                return ResponseEntity.status(HttpStatus.LOCKED).body(ErrorResponse.of(
                        "account_locked",
                        "Account is temporarily locked. Try again in "
                                + Math.max(1, secondsLeft / 60) + " minute(s).",
                        HttpStatus.LOCKED.value(),
                        request.getRequestURI()));
            }
        }

        try {
            Authentication authentication = authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(username, loginRequest.getPassword()));

            SecurityContextHolder.getContext().setAuthentication(authentication);
            UserDetailsImpl userDetails = (UserDetailsImpl) authentication.getPrincipal();

            // Load fresh user row for stamping login metadata + clearing counters.
            User user = userRepository.findByUsername(userDetails.getUsername())
                    .orElseThrow(() -> new IllegalStateException("Authenticated user missing from DB"));
            user.setFailedLoginAttempts(0);
            user.setLockedUntil(null);
            user.setLastLoginAt(Instant.now());
            user.setLastLoginIp(clientIp(request));
            userRepository.save(user);

            String accessToken = jwtUtils.generateAccessToken(userDetails);
            RefreshTokenService.Issued issued =
                    refreshTokenService.issue(user, request.getHeader("User-Agent"), clientIp(request));

            List<String> roles = userDetails.getAuthorities().stream()
                    .map(item -> item.getAuthority())
                    .collect(Collectors.toList());

            logger.info("User '{}' logged in successfully from {}", username, clientIp(request));

            return ResponseEntity.ok(new JwtResponse(
                    accessToken,
                    issued.rawToken(),
                    jwtUtils.getAccessTokenTtlSeconds(),
                    refreshTokenService.getRefreshTtlSeconds(),
                    Instant.now().getEpochSecond(),
                    userDetails.getId(),
                    userDetails.getUsername(),
                    roles));

        } catch (BadCredentialsException e) {
            recordFailedAttempt(existingUserOpt.orElse(null), username, request);
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(ErrorResponse.of(
                    "invalid_credentials",
                    "Username or password is incorrect.",
                    HttpStatus.UNAUTHORIZED.value(),
                    request.getRequestURI()));
        } catch (LockedException e) {
            return ResponseEntity.status(HttpStatus.LOCKED).body(ErrorResponse.of(
                    "account_locked",
                    "Account is temporarily locked.",
                    HttpStatus.LOCKED.value(),
                    request.getRequestURI()));
        } catch (DisabledException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(ErrorResponse.of(
                    "account_disabled",
                    "This account has been disabled.",
                    HttpStatus.FORBIDDEN.value(),
                    request.getRequestURI()));
        }
    }

    // ── Sign-up ────────────────────────────────────────────────────

    @PostMapping("/signup")
    public ResponseEntity<?> registerUser(
            @Valid @RequestBody SignupRequest signUpRequest,
            HttpServletRequest request) {

        if (userRepository.existsByUsername(signUpRequest.getUsername())) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(ErrorResponse.of(
                    "username_taken",
                    "That username is already in use.",
                    HttpStatus.CONFLICT.value(),
                    request.getRequestURI()));
        }

        User user = new User();
        user.setUsername(signUpRequest.getUsername());
        user.setPassword(encoder.encode(signUpRequest.getPassword()));
        user.setRole(Role.USER);
        user.setEnabled(true);

        try {
            userRepository.save(user);
        } catch (DataIntegrityViolationException e) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(ErrorResponse.of(
                    "username_taken",
                    "That username is already in use.",
                    HttpStatus.CONFLICT.value(),
                    request.getRequestURI()));
        }

        logger.info("New user registered: {}", signUpRequest.getUsername());

        return ResponseEntity.ok(new MessageResponse("User registered successfully!"));
    }

    // ── Refresh ────────────────────────────────────────────────────

    @PostMapping("/refresh")
    public ResponseEntity<?> refresh(
            @Valid @RequestBody RefreshTokenRequest body,
            HttpServletRequest request) {

        RefreshTokenService.Issued issued;
        try {
            issued = refreshTokenService.rotate(
                    body.getRefreshToken(),
                    request.getHeader("User-Agent"),
                    clientIp(request));
        } catch (RefreshTokenService.RefreshTokenException ex) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(ErrorResponse.of(
                    ex.getMessage(),
                    switch (ex.getMessage()) {
                        case "unknown_refresh_token" -> "Refresh token is not recognized.";
                        case "refresh_token_expired" -> "Refresh token has expired. Please sign in again.";
                        case "refresh_token_revoked" -> "Refresh token has been revoked. Please sign in again.";
                        default -> "Refresh failed.";
                    },
                    HttpStatus.UNAUTHORIZED.value(),
                    request.getRequestURI()));
        }

        User user = userRepository.findById(issued.userId())
                .orElseThrow(() -> new RefreshTokenService.RefreshTokenException("unknown_refresh_token"));

        if (!user.isEnabled()) {
            refreshTokenService.revokeAllForUser(user);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(ErrorResponse.of(
                    "account_disabled",
                    "This account has been disabled.",
                    HttpStatus.FORBIDDEN.value(),
                    request.getRequestURI()));
        }

        UserDetailsImpl details = UserDetailsImpl.build(user);
        String access = jwtUtils.generateAccessToken(details);

        List<String> roles = details.getAuthorities().stream()
                .map(a -> a.getAuthority())
                .collect(Collectors.toList());

        return ResponseEntity.ok(new JwtResponse(
                access,
                issued.rawToken(),
                jwtUtils.getAccessTokenTtlSeconds(),
                refreshTokenService.getRefreshTtlSeconds(),
                Instant.now().getEpochSecond(),
                user.getId(),
                user.getUsername(),
                roles));
    }

    // ── Logout ─────────────────────────────────────────────────────

    @PostMapping("/logout")
    public ResponseEntity<?> logout(@RequestBody(required = false) RefreshTokenRequest body) {
        if (body != null && body.getRefreshToken() != null) {
            refreshTokenService.revoke(body.getRefreshToken());
        }
        SecurityContextHolder.clearContext();
        return ResponseEntity.ok(new MessageResponse("Logged out."));
    }

    // ── Me ─────────────────────────────────────────────────────────

    @GetMapping("/me")
    public ResponseEntity<?> me(@AuthenticationPrincipal UserDetailsImpl principal) {
        if (principal == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(ErrorResponse.of(
                    "unauthenticated",
                    "Authentication is required to access this resource.",
                    HttpStatus.UNAUTHORIZED.value(),
                    "/api/auth/me"));
        }
        return userRepository.findByUsername(principal.getUsername())
                .<ResponseEntity<?>>map(u -> ResponseEntity.ok(UserProfileResponse.from(u)))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(ErrorResponse.of(
                        "unauthenticated",
                        "User no longer exists.",
                        HttpStatus.UNAUTHORIZED.value(),
                        "/api/auth/me")));
    }

    // ── Helpers ────────────────────────────────────────────────────

    private void recordFailedAttempt(User existing, String username, HttpServletRequest request) {
        logger.warn("Failed login attempt for '{}' from {}", username, clientIp(request));
        if (existing == null) return;
        int attempts = existing.getFailedLoginAttempts() + 1;
        existing.setFailedLoginAttempts(attempts);
        if (attempts >= maxFailedAttempts) {
            existing.setLockedUntil(Instant.now().plus(Duration.ofMinutes(lockoutDurationMinutes)));
            existing.setFailedLoginAttempts(0);
            logger.warn("Account '{}' locked until {} after {} failed attempts",
                    username, existing.getLockedUntil(), attempts);
        }
        userRepository.save(existing);
    }

    private String clientIp(HttpServletRequest req) {
        String xff = req.getHeader("X-Forwarded-For");
        if (xff != null && !xff.isBlank()) {
            // X-Forwarded-For can be a list: client, proxy1, proxy2. The first is the client.
            int comma = xff.indexOf(',');
            return (comma > 0 ? xff.substring(0, comma) : xff).trim();
        }
        return req.getRemoteAddr();
    }
}
