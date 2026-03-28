package com.example.aimoderation.model;

/**
 * Categories of inappropriate content that can be detected in images.
 */
public enum ImageContentCategory {
    ADULT,              // Adult/sexual content
    VIOLENCE,           // Violence/gore
    HATE_SYMBOLS,       // Hate symbols/extremist content
    DRUGS,              // Drug-related content
    WEAPONS,            // Weapons
    SELF_HARM,          // Self-harm content
    GRAPHIC_MEDICAL,    // Graphic medical content
    GAMBLING,           // Gambling-related content
    SPAM,               // Spam/misleading content
    OTHER               // Other inappropriate content
}
