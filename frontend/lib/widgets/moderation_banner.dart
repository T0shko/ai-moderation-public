import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Simple user-facing moderation result — no debug jargon.
class ModerationBanner extends StatelessWidget {
  final String status;
  final List<String> categories;
  final bool compact;

  const ModerationBanner({
    super.key,
    required this.status,
    this.categories = const [],
    this.compact = false,
  });

  factory ModerationBanner.fromScan(Map<String, dynamic> scan, {bool compact = false}) {
    final cats = (scan['categories'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];
    return ModerationBanner(
      status: scan['status']?.toString() ?? 'UNKNOWN',
      categories: cats,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = status.toUpperCase();
    final blocked = s == 'REJECTED' || s == 'FLAGGED';
    final safe = s == 'SAFE';

    if (safe) {
      return _card(
        emoji: '✅',
        title: 'Photo approved',
        subtitle: 'You can send this image.',
        bg: AppTheme.olive.withValues(alpha: 0.12),
        border: AppTheme.olive,
        accent: AppTheme.olive,
      );
    }

    if (blocked) {
      return _card(
        emoji: '🚫',
        title: 'Photo not allowed',
        subtitle: _blockedSubtitle(categories),
        bg: AppTheme.rust.withValues(alpha: 0.1),
        border: AppTheme.rust,
        accent: AppTheme.rust,
      );
    }

    if (s == 'ERROR') {
      return _card(
        emoji: '⚠️',
        title: 'Could not check photo',
        subtitle: 'Try another image or try again later.',
        bg: AppTheme.honey.withValues(alpha: 0.15),
        border: AppTheme.honey,
        accent: AppTheme.honey,
      );
    }

    return _card(
      emoji: '🔍',
      title: 'Checking…',
      subtitle: 'Hang on a moment.',
      bg: AppTheme.paper,
      border: AppTheme.hairline,
      accent: AppTheme.textSecondary,
    );
  }

  String _blockedSubtitle(List<String> cats) {
    if (cats.isEmpty) {
      return 'This image breaks our community rules.';
    }
    final label = _friendlyCategory(cats.first);
    return 'Detected: $label — not allowed here.';
  }

  static String _friendlyCategory(String raw) {
    return switch (raw.toUpperCase()) {
      'ADULT' => 'adult content',
      'WEAPONS' => 'weapons',
      'VIOLENCE' => 'violence',
      'HATE_SYMBOLS' => 'hate symbols',
      'DRUGS' => 'drugs',
      'SPAM' => 'spam',
      'SELF_HARM' => 'self-harm',
      'OTHER' => 'restricted content',
      _ => raw.toLowerCase().replaceAll('_', ' '),
    };
  }

  Widget _card({
    required String emoji,
    required String title,
    required String subtitle,
    required Color bg,
    required Color border,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 6 : 10),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: TextStyle(fontSize: compact ? 26 : 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.body(
                    size: compact ? 14 : 15,
                    weight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTheme.body(
                    size: compact ? 13 : 14,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while TriGuard is running.
class ModerationScanningBanner extends StatelessWidget {
  const ModerationScanningBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.persimmonSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.persimmon.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Text('🔎', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scanning your photo…',
                  style: AppTheme.body(
                    size: 15,
                    weight: FontWeight.w600,
                    color: AppTheme.persimmon,
                  ),
                ),
                const SizedBox(height: 4),
                const LinearProgressIndicator(
                  minHeight: 3,
                  color: AppTheme.persimmon,
                  backgroundColor: AppTheme.hairline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
