package com.example.aimoderation.dto;

import com.example.aimoderation.model.User;

public class UserPublicDto {
    private Long id;
    private String username;
    private String role;

    public static UserPublicDto from(User user) {
        UserPublicDto dto = new UserPublicDto();
        dto.id = user.getId();
        dto.username = user.getUsername();
        dto.role = user.getRole() != null ? user.getRole().name() : null;
        return dto;
    }

    public Long getId() { return id; }
    public String getUsername() { return username; }
    public String getRole() { return role; }
}
