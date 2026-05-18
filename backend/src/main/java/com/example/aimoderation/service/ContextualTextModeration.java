package com.example.aimoderation.service;

import org.springframework.stereotype.Component;

import java.util.Set;
import java.util.regex.Pattern;

/**
 * Context-aware rules for Bulgarian/English phrases where a substring alone is not toxic
 * (e.g. "maika ti e hubava" vs "maika ti da eba").
 */
@Component
public class ContextualTextModeration {

    /** Standalone tokens that must not trigger instant block without context check. */
    private static final Set<String> AMBIGUOUS_FAMILY_PREFIXES = Set.of(
            "maika ti", "mayka ti", "majka ti", "майка ти",
            "bashta ti", "bashtati", "баща ти");

    private static final Pattern FAMILY_INSULT = Pattern.compile(
            "(maika|mayka|majka|майка)\\s+ti\\s+.*(eba|ebi|ebat|putk|kurv|prost|glup|pedal|mudal|shib|prasht|kuch|kopel)|"
                    + "da\\s+ti\\s+eba\\s+maikat|"
                    + "eba\\s+ti\\s+maikat|"
                    + "ebi\\s+si\\s+maikat|"
                    + "майка\\s+ти\\s+да\\s+еба|"
                    + "да\\s+ти\\s+еба\\s+майката",
            Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

    private static final Pattern FAMILY_BENIGN = Pattern.compile(
            "(maika|mayka|majka|майка)\\s+ti\\s+"
                    + "(e\\s+|е\\s+)?(mnogo\\s+|mn\\.|naj\\s*|най\\s*)?"
                    + "(hubav[ao]?|hubava|krasiv[ao]?|krasiw[ao]?|qk[ao]?|qko|dobr[ao]?|dobar|dobra|"
                    + "umn[ao]?|umna|super|golqm|golyam|lepav[ao]?|prekrasen|prekrasna|sladuk|sladka|"
                    + "xubav[ao]?|хубав[ao]?|красив[ao]?|добр[ао]?|умн[ао]?)",
            Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

    /** Colloquial BG phrases — not insults (e.g. "maika ti idva nasam"). */
    private static final Pattern FAMILY_COLLOQUIAL = Pattern.compile(
            "(maika|mayka|majka|майка)\\s+ti\\s+.*(idva|ide|doidva|doliza)\\s*(nasam|nasa|tuk|tuka|viene)|"
                    + "(maika|mayka|majka|майка)\\s+ti\\s+(idva|ide)\\s+(nasam|tuk)",
            Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

    private static final Pattern FAMILY_BENIGN_SHORT = Pattern.compile(
            "(maika|mayka|majka|майка)\\s+ti\\s+(e\\s+|е\\s+)?(hubavo|hubava|hubav|хубава|хубав)",
            Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

    public enum ContextVerdict {
        BENIGN, MALICIOUS, NEUTRAL
    }

    public ContextVerdict analyze(String normalizedText) {
        if (normalizedText == null || normalizedText.isBlank()) {
            return ContextVerdict.NEUTRAL;
        }
        if (FAMILY_INSULT.matcher(normalizedText).find()) {
            return ContextVerdict.MALICIOUS;
        }
        if (FAMILY_BENIGN.matcher(normalizedText).find()
                || FAMILY_BENIGN_SHORT.matcher(normalizedText).find()
                || FAMILY_COLLOQUIAL.matcher(normalizedText).find()) {
            return ContextVerdict.BENIGN;
        }
        if (containsAmbiguousFamilyPrefix(normalizedText) && hasNearbyPositiveTone(normalizedText)) {
            return ContextVerdict.BENIGN;
        }
        return ContextVerdict.NEUTRAL;
    }

    public boolean isBenignFamilyContext(String normalizedText) {
        return analyze(normalizedText) == ContextVerdict.BENIGN;
    }

    public boolean isMaliciousFamilyContext(String normalizedText) {
        return analyze(normalizedText) == ContextVerdict.MALICIOUS;
    }

    public boolean isAmbiguousToken(String token) {
        if (token == null) return false;
        String t = token.trim().toLowerCase();
        return AMBIGUOUS_FAMILY_PREFIXES.contains(t);
    }

    /** Skip instant toxic hit when the full message is benign in context. */
    public boolean shouldSuppressTokenMatch(String normalizedText, String matchedToken) {
        if (!isAmbiguousToken(matchedToken)) {
            return false;
        }
        ContextVerdict verdict = analyze(normalizedText);
        return verdict == ContextVerdict.BENIGN;
    }

    public boolean containsAmbiguousFamilyPrefixPublic(String text) {
        return containsAmbiguousFamilyPrefix(text);
    }

    private boolean containsAmbiguousFamilyPrefix(String text) {
        for (String prefix : AMBIGUOUS_FAMILY_PREFIXES) {
            if (text.contains(prefix)) {
                return true;
            }
        }
        return false;
    }

    private boolean hasNearbyPositiveTone(String normalized) {
        String[] positiveHints = {
                "hubav", "hubava", "hubavo", "krasiv", "krasiva", "dobar", "dobra", "umna", "umn",
                "super", "obicham", "love", "beautiful", "great", "best", "qko", "qka", "bravo",
                "хубав", "хубава", "красив", "добра", "добър", "умна", "супер"
        };
        for (String hint : positiveHints) {
            if (normalized.contains(hint)) {
                return true;
            }
        }
        return false;
    }
}
