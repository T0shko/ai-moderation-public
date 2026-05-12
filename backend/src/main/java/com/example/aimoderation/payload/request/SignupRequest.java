package com.example.aimoderation.payload.request;

import java.util.Set;

import jakarta.validation.constraints.*;

public class SignupRequest {
    @NotBlank(message = "Username is required")
    @Size(min = 3, max = 30, message = "Username must be between 3 and 30 characters")
    @Pattern(regexp = "^[A-Za-z0-9._-]+$",
            message = "Username may only contain letters, digits, '.', '_' and '-'")
    private String username;

    @NotBlank(message = "Password is required")
    @Size(min = 8, max = 128, message = "Password must be at least 8 characters")
    @Pattern(regexp = "^(?=.*[A-Za-z])(?=.*\\d).+$",
            message = "Password must contain at least one letter and one number")
    private String password;

    private Set<String> role;

    public String getUsername() { return username; }
    public void setUsername(String username) {
        this.username = username == null ? null : username.trim();
    }

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }

    public Set<String> getRole() { return this.role; }
    public void setRole(Set<String> role) { this.role = role; }
}
