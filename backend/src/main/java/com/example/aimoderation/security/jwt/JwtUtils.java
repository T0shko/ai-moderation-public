package com.example.aimoderation.security.jwt;

import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.List;
import java.util.UUID;

import javax.crypto.SecretKey;

import com.example.aimoderation.security.services.UserDetailsImpl;
import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import io.jsonwebtoken.security.SignatureException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.stereotype.Component;

import jakarta.annotation.PostConstruct;

/**
 * Signs and validates access JWTs.
 *
 * Hardening:
 *   - HS512 signing key with strict minimum length (rejects weak secrets).
 *   - Short expiry by default (15 min); refresh tokens carry the long session.
 *   - Standard claims (iss, aud, sub, iat, exp, jti) plus role claim.
 *   - Specific exceptions surface to callers so they can map to 401/403 codes
 *     instead of a single "invalid" bucket.
 */
@Component
public class JwtUtils {
    private static final Logger logger = LoggerFactory.getLogger(JwtUtils.class);
    private static final int MIN_SECRET_BYTES = 64; // 512 bits — required by HS512

    @Value("${jwt.secret}")
    private String jwtSecret;

    @Value("${jwt.access.ttl-ms:900000}") // 15 minutes
    private long accessTokenTtlMs;

    @Value("${jwt.issuer:ai-moderation}")
    private String issuer;

    @Value("${jwt.audience:ai-moderation-app}")
    private String audience;

    @Value("${jwt.clock-skew-seconds:30}")
    private long clockSkewSeconds;

    private SecretKey signingKey;

    @PostConstruct
    public void init() {
        if (jwtSecret == null || jwtSecret.isBlank()) {
            throw new IllegalStateException(
                    "jwt.secret is not configured. Set the JWT_SECRET environment variable.");
        }
        if (jwtSecret.contains("change_this") || jwtSecret.contains("your_jwt_secret")) {
            logger.warn("jwt.secret uses a placeholder value — set JWT_SECRET before production deploy.");
        }
        byte[] keyBytes = jwtSecret.getBytes(StandardCharsets.UTF_8);
        if (keyBytes.length < MIN_SECRET_BYTES) {
            throw new IllegalStateException(
                    "jwt.secret is too short. Provide at least " + MIN_SECRET_BYTES
                            + " bytes (got " + keyBytes.length + "). "
                            + "Generate one with: openssl rand -base64 64");
        }
        signingKey = Keys.hmacShaKeyFor(keyBytes);
        logger.info("JWT signing key initialized (issuer='{}', audience='{}', access-ttl={}s)",
                issuer, audience, accessTokenTtlMs / 1000);
    }

    public long getAccessTokenTtlSeconds() {
        return accessTokenTtlMs / 1000;
    }

    public String generateAccessToken(UserDetailsImpl user) {
        Date now = new Date();
        Date exp = new Date(now.getTime() + accessTokenTtlMs);

        List<String> roles = user.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .toList();

        return Jwts.builder()
                .id(UUID.randomUUID().toString())
                .issuer(issuer)
                .audience().add(audience).and()
                .subject(user.getUsername())
                .claim("uid", user.getId())
                .claim("roles", roles)
                .issuedAt(now)
                .expiration(exp)
                .signWith(signingKey, Jwts.SIG.HS512)
                .compact();
    }

    public Jws<Claims> parse(String token) {
        return Jwts.parser()
                .verifyWith(signingKey)
                .requireIssuer(issuer)
                .requireAudience(audience)
                .clockSkewSeconds(clockSkewSeconds)
                .build()
                .parseSignedClaims(token);
    }

    public String getUserNameFromJwtToken(String token) {
        return parse(token).getPayload().getSubject();
    }

    /** Returns a validation result with a specific failure code, never throws. */
    public Validation validate(String authToken) {
        try {
            parse(authToken);
            return Validation.ok();
        } catch (ExpiredJwtException e) {
            return Validation.fail("token_expired");
        } catch (SignatureException e) {
            logger.warn("Invalid JWT signature");
            return Validation.fail("invalid_signature");
        } catch (MalformedJwtException e) {
            return Validation.fail("malformed_token");
        } catch (UnsupportedJwtException e) {
            return Validation.fail("unsupported_token");
        } catch (IllegalArgumentException e) {
            return Validation.fail("empty_token");
        } catch (JwtException e) {
            return Validation.fail("invalid_token");
        }
    }

    public boolean validateJwtToken(String authToken) {
        return validate(authToken).valid();
    }

    public record Validation(boolean valid, String code) {
        public static Validation ok() { return new Validation(true, null); }
        public static Validation fail(String code) { return new Validation(false, code); }
    }
}
