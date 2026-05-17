import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// PRESSROOM — editorial risograph design system.
///
/// Two-color print feel: warm ink on cream paper, persimmon as the single
/// punch accent, ledger-green and rust used only for semantic signal.
/// Typography pairs an italic-friendly serif display with newsprint body
/// copy and a strict monospace for numerics, badges, IDs and small caps.
class AppTheme {
  // ── Ink & paper ────────────────────────────────────────────────
  static const Color ink = Color(0xFF1A1614);
  static const Color inkSoft = Color(0xFF2B2520);
  static const Color paper = Color(0xFFF4EFE3);
  static const Color paperLight = Color(0xFFFBF8F0);
  static const Color paperDeep = Color(0xFFE7E0CD);
  static const Color paperInk = Color(0xFFDED5C0);

  // ── The single accent ──────────────────────────────────────────
  static const Color persimmon = Color(0xFFD14517);
  static const Color persimmonSoft = Color(0xFFFBE3D5);

  // ── Semantic prints ────────────────────────────────────────────
  static const Color olive = Color(0xFF4F5D3B);
  static const Color oliveSoft = Color(0xFFE6E9D7);
  static const Color rust = Color(0xFF8C2B1F);
  static const Color rustSoft = Color(0xFFF3D8D2);
  static const Color honey = Color(0xFFB07A19);
  static const Color honeySoft = Color(0xFFF1E2BE);
  static const Color azure = Color(0xFF2E4F73);
  static const Color azureSoft = Color(0xFFD8E0EA);

  // ── Type / borders ─────────────────────────────────────────────
  static const Color textPrimary = ink;
  static const Color textSecondary = Color(0xFF494037);
  static const Color textTertiary = Color(0xFF7C7367);
  static const Color hairline = Color(0xFFC9C1AF);
  static const Color hairlineSoft = Color(0xFFE0D7C3);

  // ── Compatibility aliases (kept so existing screens keep compiling) ──
  static const Color primary = ink;
  static const Color primaryLight = inkSoft;
  static const Color primaryDark = Color(0xFF0E0B09);
  static const Color accent = persimmon;
  static const Color success = olive;
  static const Color warning = honey;
  static const Color error = rust;
  static const Color info = azure;

  static const Color veridian = olive;
  static const Color veridianDark = Color(0xFF3A4530);
  static const Color veridianSoft = oliveSoft;
  static const Color spice = persimmon;
  static const Color spiceSoft = persimmonSoft;
  static const Color rose = persimmon;
  static const Color mint = olive;
  static const Color sky = azure;
  static const Color slate = Color(0xFF6B5F50);
  static const Color coral = persimmon;
  static const Color amber = honey;
  static const Color peach = persimmon;
  static const Color plum = ink;

  static const Color bgDeep = paper;
  static const Color bgPrimary = paper;
  static const Color bgSecondary = paperLight;
  static const Color bgTertiary = paperDeep;
  static const Color bgElevated = paperLight;
  static const Color bgInset = paperInk;
  static const Color borderDefault = hairline;
  static const Color borderMuted = hairlineSoft;
  static const Color borderActive = ink;

  // ── Gradients (kept solid-ish for press feel) ──────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [ink, inkSoft],
  );
  static const LinearGradient accentGradient = LinearGradient(
    colors: [persimmon, Color(0xFFB13510)],
  );
  static const LinearGradient warmGradient = LinearGradient(
    colors: [ink, persimmon],
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [olive, Color(0xFF3B4830)],
  );
  static const LinearGradient dangerGradient = LinearGradient(
    colors: [rust, persimmon],
  );
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [paperLight, paper],
  );

  // ── Hard offset (press) shadow ─────────────────────────────────
  static List<BoxShadow> hardShadow({
    Color color = ink,
    double offset = 4,
    double alpha = 1,
  }) => [
    BoxShadow(
      color: color.withValues(alpha: alpha),
      offset: Offset(offset, offset),
      blurRadius: 0,
    ),
  ];

  static List<BoxShadow> softShadowList() => [
    BoxShadow(
      color: ink.withValues(alpha: 0.05),
      offset: const Offset(0, 6),
      blurRadius: 14,
    ),
  ];

  // Back-compat helpers used by older code paths.
  static List<BoxShadow> glow(Color color, [double intensity = 0.18]) => [
    BoxShadow(
      color: ink.withValues(alpha: intensity * 0.4),
      offset: const Offset(3, 3),
      blurRadius: 0,
    ),
  ];

  static List<BoxShadow> get softShadow => softShadowList();

  // ── Radii ──────────────────────────────────────────────────────
  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 14;
  static const double radiusXl = 20;
  static const double radiusRound = 100;

  // ── Typography helpers ─────────────────────────────────────────
  /// Display serif — Fraunces italic-leaning, used for hero titles.
  static TextStyle display({
    double size = 32,
    FontWeight weight = FontWeight.w600,
    Color? color,
    FontStyle style = FontStyle.normal,
    double letterSpacing = -0.8,
    double? height,
  }) => GoogleFonts.fraunces(
    fontSize: size,
    fontWeight: weight,
    color: color ?? textPrimary,
    fontStyle: style,
    letterSpacing: letterSpacing,
    height: height ?? 1.05,
  );

  /// Body — newsprint Newsreader.
  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.55,
    FontStyle style = FontStyle.normal,
  }) => GoogleFonts.newsreader(
    fontSize: size,
    fontWeight: weight,
    color: color ?? textSecondary,
    height: height,
    fontStyle: style,
  );

  /// Mono — for numerals, IDs, ruled labels.
  static TextStyle mono({
    double size = 11,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double letterSpacing = 1.6,
  }) => GoogleFonts.dmMono(
    fontSize: size,
    fontWeight: weight,
    color: color ?? textSecondary,
    letterSpacing: letterSpacing,
  );

  /// Small caps label (mono, uppercase). Caller should uppercase text.
  static TextStyle label({
    double size = 10,
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) => mono(
    size: size,
    weight: weight,
    color: color ?? textTertiary,
    letterSpacing: 2.4,
  );

  // ── Theme data ─────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final scheme = ColorScheme.light(
      primary: ink,
      secondary: persimmon,
      tertiary: olive,
      surface: paperLight,
      error: rust,
      onPrimary: paperLight,
      onSecondary: paperLight,
      onSurface: ink,
      outline: hairline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: paper,
      colorScheme: scheme,
      textTheme: _textTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: paperLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: display(size: 22, weight: FontWeight.w700),
        iconTheme: const IconThemeData(color: ink),
      ),
      cardTheme: CardThemeData(
        color: paperLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: hairline),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 0,
          vertical: 14,
        ),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: ink, width: 1.5),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: rust),
        ),
        labelStyle: label(),
        floatingLabelStyle: label(color: persimmon),
        hintStyle: body(color: textTertiary),
        prefixIconColor: textTertiary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: mono(color: paperLight, size: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: paperLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: const BorderSide(color: ink),
        ),
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: hairline,
        labelColor: ink,
        unselectedLabelColor: textTertiary,
        indicatorColor: persimmon,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: persimmon, width: 2.5),
        ),
        labelStyle: mono(size: 11, color: ink, weight: FontWeight.w600),
        unselectedLabelStyle: mono(size: 11, color: textTertiary),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: ink,
        inactiveTrackColor: hairlineSoft,
        thumbColor: persimmon,
        overlayColor: Color(0x33D14517),
        trackHeight: 2,
      ),
    );
  }

  static ThemeData get darkTheme => lightTheme;

  static TextTheme _textTheme() {
    final base = ThemeData.light().textTheme;
    return GoogleFonts.newsreaderTextTheme(base).copyWith(
      displayLarge: display(size: 44, weight: FontWeight.w700),
      headlineMedium: display(size: 28, weight: FontWeight.w700),
      titleLarge: display(size: 22, weight: FontWeight.w600),
      titleMedium: GoogleFonts.newsreader(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: body(size: 16),
      bodyMedium: body(size: 14),
      bodySmall: body(size: 12, color: textTertiary),
      labelLarge: mono(size: 12, color: textPrimary, weight: FontWeight.w600),
    );
  }
}
