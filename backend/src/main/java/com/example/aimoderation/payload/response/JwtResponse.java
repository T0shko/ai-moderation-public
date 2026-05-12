package com.example.aimoderation.payload.response;

import java.util.List;

/**
 * Returned by /api/auth/signin and /api/auth/refresh.
 *
 * Field naming kept in JSON form: accessToken, refreshToken, tokenType,
 * expiresIn (seconds), issuedAt (epoch seconds), plus user identity.
 */
public class JwtResponse {
    private String accessToken;
    private String refreshToken;
    private String tokenType = "Bearer";
    private long expiresIn;       // seconds until access token expires
    private long refreshExpiresIn; // seconds until refresh token expires
    private long issuedAt;        // epoch seconds
    private Long id;
    private String username;
    private List<String> roles;

    public JwtResponse() {}

    public JwtResponse(String accessToken, String refreshToken, long expiresIn,
                       long refreshExpiresIn, long issuedAt,
                       Long id, String username, List<String> roles) {
        this.accessToken = accessToken;
        this.refreshToken = refreshToken;
        this.expiresIn = expiresIn;
        this.refreshExpiresIn = refreshExpiresIn;
        this.issuedAt = issuedAt;
        this.id = id;
        this.username = username;
        this.roles = roles;
    }

    public String getAccessToken() { return accessToken; }
    public void setAccessToken(String accessToken) { this.accessToken = accessToken; }

    public String getRefreshToken() { return refreshToken; }
    public void setRefreshToken(String refreshToken) { this.refreshToken = refreshToken; }

    public String getTokenType() { return tokenType; }
    public void setTokenType(String tokenType) { this.tokenType = tokenType; }

    public long getExpiresIn() { return expiresIn; }
    public void setExpiresIn(long expiresIn) { this.expiresIn = expiresIn; }

    public long getRefreshExpiresIn() { return refreshExpiresIn; }
    public void setRefreshExpiresIn(long refreshExpiresIn) { this.refreshExpiresIn = refreshExpiresIn; }

    public long getIssuedAt() { return issuedAt; }
    public void setIssuedAt(long issuedAt) { this.issuedAt = issuedAt; }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public List<String> getRoles() { return roles; }
    public void setRoles(List<String> roles) { this.roles = roles; }
}
