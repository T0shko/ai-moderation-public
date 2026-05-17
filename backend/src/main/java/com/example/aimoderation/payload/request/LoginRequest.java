package com.example.aimoderation.payload.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public class LoginRequest {
    @NotBlank(message = "Username is required")
    @Size(min = 3, max = 50, message = "Username must be between 3 and 50 characters")
    private String username;

    @NotBlank(message = "Password is required")
    @Size(min = 6, max = 128, message = "Password length is out of bounds")
    private String password;

    public String getUsername() { return username; }
    public void setUsername(String username) {
        this.username = username == null ? null : username.trim();
    }

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
}
