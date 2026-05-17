package com.example.aimoderation.security.services;

import com.example.aimoderation.model.RefreshToken;
import com.example.aimoderation.model.User;
import com.example.aimoderation.repository.RefreshTokenRepository;

import jakarta.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Optional;

/**
 * Issues, validates, rotates, and revokes opaque refresh tokens.
 *
 * Storage model:
 *   - Raw refresh token = 256-bit secure random, base64url encoded (no padding).
 *   - We persist ONLY a SHA-256 hash of the raw token, so a DB leak does not
 *     allow an attacker to mint sessions.
 *   - Tokens are single-use: validating a refresh token rotates it and revokes
 *     the previous record. Reuse of a revoked-but-unexpired token is treated
 *     as compromise and triggers cascade revocation for that user.
 */
@Service
public class RefreshTokenService {

    private static final Logger logger = LoggerFactory.getLogger(RefreshTokenService.class);
    private static final int RAW_TOKEN_BYTES = 32; // 256 bits

    private final RefreshTokenRepository repository;
    private final SecureRandom random = new SecureRandom();

    @Value("${jwt.refresh.ttl-days:14}")
    private long refreshTtlDays;

    public RefreshTokenService(RefreshTokenRepository repository) {
        this.repository = repository;
    }

    @PostConstruct
    public void onStartup() {
        logger.info("RefreshTokenService configured (ttl={} days)", refreshTtlDays);
    }

    public record Issued(String rawToken, RefreshToken record) {}

    /** Issues a brand-new refresh token for the given user (no rotation). */
    @Transactional
    public Issued issue(User user, String userAgent, String ip) {
        String raw = generateRawToken();
        RefreshToken record = persistToken(user, raw, userAgent, ip);
        return new Issued(raw, record);
    }

    /**
     * Rotates a refresh token: validates the presented raw token, issues a new
     * one, marks the old one as revoked/replaced. Returns the new raw token.
     *
     * Throws if the token is unknown, expired, or already revoked.
     * Token reuse (a revoked-but-unexpired token presented again) triggers
     * a security cascade: all sessions for the user are revoked.
     */
    @Transactional
    public Issued rotate(String rawToken, String userAgent, String ip) {
        String hash = sha256(rawToken);
        RefreshToken existing = repository.findByTokenHash(hash)
                .orElseThrow(() -> new RefreshTokenException("unknown_refresh_token"));

        if (existing.isExpired()) {
            throw new RefreshTokenException("refresh_token_expired");
        }
        if (existing.isRevoked()) {
            // Replay attempt → assume compromise, revoke everything for this user.
            int revoked = repository.revokeAllForUser(existing.getUser(), Instant.now());
            logger.warn("Refresh token reuse detected for user '{}'; revoked {} active sessions",
                    existing.getUser().getUsername(), revoked);
            throw new RefreshTokenException("refresh_token_revoked");
        }

        User user = existing.getUser();
        String newRaw = generateRawToken();
        String newHash = sha256(newRaw);

        existing.setRevoked(true);
        existing.setRevokedAt(Instant.now());
        existing.setReplacedBy(newHash);
        repository.save(existing);

        RefreshToken newRecord = persistToken(user, newRaw, userAgent, ip);
        return new Issued(newRaw, newRecord);
    }

    /** Revokes a single refresh token, e.g. on /logout. Idempotent. */
    @Transactional
    public void revoke(String rawToken) {
        if (rawToken == null || rawToken.isBlank()) return;
        repository.findByTokenHash(sha256(rawToken)).ifPresent(rt -> {
            if (!rt.isRevoked()) {
                rt.setRevoked(true);
                rt.setRevokedAt(Instant.now());
                repository.save(rt);
            }
        });
    }

    @Transactional
    public int revokeAllForUser(User user) {
        return repository.revokeAllForUser(user, Instant.now());
    }

    public Optional<RefreshToken> find(String rawToken) {
        return repository.findByTokenHash(sha256(rawToken));
    }

    public long getRefreshTtlSeconds() {
        return Duration.ofDays(refreshTtlDays).getSeconds();
    }

    /** Nightly purge of expired tokens. Runs at 03:17 server time. */
    @Scheduled(cron = "0 17 3 * * *")
    @Transactional
    public void purgeExpired() {
        int removed = repository.deleteAllExpired(Instant.now());
        if (removed > 0) {
            logger.info("Purged {} expired refresh tokens", removed);
        }
    }

    // ── Helpers ────────────────────────────────────────────────────

    private RefreshToken persistToken(User user, String raw, String userAgent, String ip) {
        Instant now = Instant.now();
        RefreshToken rt = new RefreshToken();
        rt.setUser(user);
        rt.setTokenHash(sha256(raw));
        rt.setIssuedAt(now);
        rt.setExpiresAt(now.plus(Duration.ofDays(refreshTtlDays)));
        rt.setUserAgent(truncate(userAgent, 255));
        rt.setIpAddress(truncate(ip, 64));
        rt.setRevoked(false);
        return repository.save(rt);
    }

    private String generateRawToken() {
        byte[] bytes = new byte[RAW_TOKEN_BYTES];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static String sha256(String input) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(input.getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
        } catch (NoSuchAlgorithmException e) {
            // SHA-256 is required by every JVM; this never happens.
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }

    private static String truncate(String s, int max) {
        if (s == null) return null;
        return s.length() <= max ? s : s.substring(0, max);
    }

    public static class RefreshTokenException extends RuntimeException {
        public RefreshTokenException(String code) { super(code); }
    }
}
