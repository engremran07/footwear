import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';

/// Provides text scaling adjustments for RTL languages like Urdu and Arabic.
/// Urdu text tends to look larger due to script characteristics, so we scale it down.
class UrduTextScaler {
  UrduTextScaler._();

  /// Scale factor for Urdu text (reduces size to match visual perception of English text)
  static const double urduScaleFactor = 0.92;

  /// Scale factor for Arabic text
  static const double arabicScaleFactor = 0.95;

  /// Get the font size adjustment for the given locale
  static double getScaleFactor(AppLocale locale) {
    return switch (locale) {
      AppLocale.ur => urduScaleFactor,
      AppLocale.ar => arabicScaleFactor,
      AppLocale.en => 1.0,
    };
  }

  /// Adjust a font size based on locale
  static double scaleFontSize(double baseFontSize, AppLocale locale) {
    return baseFontSize * getScaleFactor(locale);
  }

  /// Build a TextStyle with locale-aware scaling
  static TextStyle scaleTextStyle(
    TextStyle style,
    AppLocale locale, {
    double? overrideFontSize,
  }) {
    final scaleFactor = getScaleFactor(locale);
    final fontSize = overrideFontSize ?? style.fontSize ?? 14.0;
    return style.copyWith(
      fontSize: fontSize * scaleFactor,
      height: 1.3, // Slightly increased line height for RTL readability
    );
  }
}
