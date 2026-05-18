package com.example.aimoderation.util;

import java.text.Normalizer;
import java.util.regex.Pattern;

/**
 * Shared text normalization for moderation and filter checks.
 */
public final class TextNormalizer {

    private static final Pattern ZERO_WIDTH = Pattern.compile("[\\u200B-\\u200D\\uFEFF]");
    private static final Pattern WHITESPACE = Pattern.compile("\\s+");

    private TextNormalizer() {}

    public static String normalize(String text) {
        if (text == null) return "";
        String result = Normalizer.normalize(text, Normalizer.Form.NFKC).toLowerCase().trim();
        result = ZERO_WIDTH.matcher(result).replaceAll("");
        result = collapseRepeatedChars(result);
        result = leetToAscii(result);
        result = cyrillicHomoglyphsToLatin(result);
        result = result.replaceAll("[\\-\\_\\.\\*]", "");
        result = WHITESPACE.matcher(result).replaceAll(" ");
        return result.trim();
    }

    /** Compact form for spaced-letter bypass detection (e.g. "f u c k" → "fuck"). */
    public static String compact(String normalized) {
        return normalized.replace(" ", "");
    }

    private static String collapseRepeatedChars(String text) {
        if (text.length() <= 2) return text;
        StringBuilder sb = new StringBuilder();
        sb.append(text.charAt(0));
        for (int i = 1; i < text.length(); i++) {
            char current = text.charAt(i);
            char previous = text.charAt(i - 1);
            if (i >= 2 && current == previous && text.charAt(i - 2) == previous) {
                continue;
            }
            sb.append(current);
        }
        return sb.toString();
    }

    private static String leetToAscii(String text) {
        return text
                .replace('0', 'o')
                .replace('1', 'i')
                .replace('3', 'e')
                .replace('4', 'a')
                .replace('5', 's')
                .replace('7', 't')
                .replace('@', 'a')
                .replace('$', 's')
                .replace('!', 'i');
    }

    private static String cyrillicHomoglyphsToLatin(String text) {
        return text
                .replace('а', 'a')
                .replace('в', 'b')
                .replace('е', 'e')
                .replace('к', 'k')
                .replace('м', 'm')
                .replace('н', 'h')
                .replace('о', 'o')
                .replace('р', 'p')
                .replace('с', 'c')
                .replace('т', 't')
                .replace('у', 'y')
                .replace('х', 'x')
                .replace('і', 'i');
    }
}
