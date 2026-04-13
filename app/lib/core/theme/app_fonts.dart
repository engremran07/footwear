import 'package:flutter/material.dart';

/// Centralized, locale-aware font resolver.
///
/// Returns the correct font family based on locale:
/// - 'ur' → NotoNastaliqUrdu (bundled Nastaleeq, offline)
/// - 'ar' → NotoNaskhArabic (bundled Naskh, offline)
/// - else → bundled Syne (headings) / DM Sans (body) fonts (offline)
class AppFonts {
  AppFonts._();

  static const String syneFamily = 'Syne';
  static const String dmSansFamily = 'DMSans';
  static const String urduFamily = 'NotoNastaliqUrdu';
  static const String arabicFamily = 'NotoSansArabic';

  /// Heading font for the current locale.
  static TextStyle heading(
    String locale, {
    double fontSize = 20,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
  }) {
    return switch (locale) {
      'ur' => TextStyle(
        fontFamily: urduFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 2.0,
      ),
      'ar' => TextStyle(
        fontFamily: arabicFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 1.5,
      ),
      _ => TextStyle(
        fontFamily: syneFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    };
  }

  /// Body font for the current locale.
  static TextStyle body(
    String locale, {
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
  }) {
    return switch (locale) {
      'ur' => TextStyle(
        fontFamily: urduFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 2.0,
      ),
      'ar' => TextStyle(
        fontFamily: arabicFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 1.5,
      ),
      _ => TextStyle(
        fontFamily: dmSansFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    };
  }

  /// Build a full TextTheme for the locale.
  static TextTheme textTheme(
    String locale, {
    Color textPrimary = Colors.white,
    Color textSecondary = const Color(0xFF94A3B8),
  }) {
    return TextTheme(
      headlineLarge: heading(
        locale,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      headlineMedium: heading(
        locale,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      headlineSmall: heading(
        locale,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleLarge: heading(
        locale,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleMedium: body(
        locale,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleSmall: body(
        locale,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: body(locale, fontSize: 16, color: textPrimary),
      bodyMedium: body(locale, fontSize: 14, color: textPrimary),
      bodySmall: body(locale, fontSize: 12, color: textSecondary),
      labelLarge: body(
        locale,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      labelMedium: body(
        locale,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      ),
      labelSmall: body(
        locale,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      ),
    );
  }

  /// Font family for PDF generation (picks bundled .ttf path).
  /// NotoSansArabic is used for both Urdu and Arabic in PDFs because
  /// NotoNastaliqUrdu relies on complex OpenType GSUB/GPOS features for
  /// Nastaliq shaping that the pdf package's TrueType renderer does not
  /// support, causing boxes. Naskh has full Arabic Presentation Form glyphs
  /// that work correctly with arabic_reshaper.
  static String? pdfFontAsset(String locale) {
    return switch (locale) {
      'ur' => 'assets/fonts/NotoSansArabic.ttf',
      'ar' => 'assets/fonts/NotoSansArabic.ttf',
      _ => null, // Use pdf package's built-in latin fonts
    };
  }
}
