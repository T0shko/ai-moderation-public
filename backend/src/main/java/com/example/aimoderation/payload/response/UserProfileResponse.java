package com.example.aimoderation.payload.response;

import com.example.aimoderation.model.User;

import java.time.Instant;
import java.util.List;

public record UserProfileResponse(
        Long id,
        String username,
        List<String> roles,
        boolean enabled,
        Instant lastLoginAt,
        Instant createdAt) {

    public static UserProfileResponse from(User user) {
        return new UserProfileResponse(
                user.getId(),
                user.getUsername(),
                List.of("ROLE_" + user.getRole().name()),
                user.isEnabled(),
                user.getLastLoginAt(),
                user.getCreatedAt());
    }
}
