package com.example.aimoderation.config;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Loads a single {@code .env} file from the working directory or any parent (repo root),
 * into {@link System#setProperty} for keys that are not already set in the OS environment
 * or as JVM {@code -D} properties. Intended for local dev only; production should inject env vars.
 * <p>
 * The file {@code .env} must stay gitignored; use {@code .env.example} as the committed template.
 */
public final class LocalEnvFileLoader {

    private LocalEnvFileLoader() {}

    public static void loadIfPresent() {
        Path envFile = findEnvFile();
        if (envFile == null) {
            return;
        }
        try {
            for (String raw : Files.readAllLines(envFile, StandardCharsets.UTF_8)) {
                String line = raw.strip();
                if (line.isEmpty() || line.startsWith("#")) {
                    continue;
                }
                int eq = line.indexOf('=');
                if (eq <= 0) {
                    continue;
                }
                String key = line.substring(0, eq).strip();
                String value = unquote(line.substring(eq + 1).strip());
                if (key.isEmpty()) {
                    continue;
                }
                if (alreadyDefined(key)) {
                    continue;
                }
                System.setProperty(key, value);
            }
        } catch (IOException e) {
            System.err.println("LocalEnvFileLoader: could not read " + envFile + ": " + e.getMessage());
        }
    }

    private static Path findEnvFile() {
        Path dir = Paths.get("").toAbsolutePath().normalize();
        for (int depth = 0; depth < 8 && dir != null; depth++) {
            Path candidate = dir.resolve(".env");
            if (Files.isRegularFile(candidate)) {
                return candidate;
            }
            dir = dir.getParent();
        }
        return null;
    }

    private static boolean alreadyDefined(String key) {
        String env = System.getenv(key);
        if (env != null && !env.isEmpty()) {
            return true;
        }
        String prop = System.getProperty(key);
        return prop != null && !prop.isEmpty();
    }

    private static String unquote(String s) {
        if (s.length() >= 2) {
            char a = s.charAt(0);
            char b = s.charAt(s.length() - 1);
            if ((a == '"' && b == '"') || (a == '\'' && b == '\'')) {
                return s.substring(1, s.length() - 1);
            }
        }
        return s;
    }
}
