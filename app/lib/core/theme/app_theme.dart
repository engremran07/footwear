import 'package:flutter/material.dart';
import '../constants/app_brand.dart';
import '../l10n/app_locale.dart';
import '../utils/text_scaler.dart' as urdu_text;

class AppTheme {
  AppTheme._();

  // Semantic colours exposed for widgets
  static const Color success = AppBrand.successColor;
  static const Color warning = AppBrand.warningColor;

  /// Returns the correct [fontFamily] for the given locale.
  static String? fontFamilyFor(AppLocale locale) {
    switch (locale) {
      case AppLocale.ur:
        return AppBrand.fontFamilyUrdu;
      case AppLocale.ar:
        return AppBrand.fontFamilyArabic;
      case AppLocale.en:
        return null; // default Roboto
    }
  }

  /// Creates a light theme with the given locale's font.
  static ThemeData lightTheme(AppLocale locale) {
    final fontFamily = fontFamilyFor(locale);
    final scaleFactor = urdu_text.UrduTextScaler.getScaleFactor(locale);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppBrand.primaryColor,
      secondary: AppBrand.secondaryColor,
      error: AppBrand.errorColor,
      brightness: Brightness.light,
    );

    // Build scaled text theme for RTL languages
    final baseTextTheme = ThemeData(fontFamily: fontFamily).textTheme;
    final textTheme = TextTheme(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: (baseTextTheme.displayLarge?.fontSize ?? 57) * scaleFactor,
        height: 1.2,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: (baseTextTheme.displayMedium?.fontSize ?? 45) * scaleFactor,
        height: 1.2,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: (baseTextTheme.displaySmall?.fontSize ?? 36) * scaleFactor,
        height: 1.3,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: (baseTextTheme.headlineLarge?.fontSize ?? 32) * scaleFactor,
        height: 1.3,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: (baseTextTheme.headlineMedium?.fontSize ?? 28) * scaleFactor,
        height: 1.3,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: (baseTextTheme.headlineSmall?.fontSize ?? 24) * scaleFactor,
        height: 1.3,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: (baseTextTheme.titleLarge?.fontSize ?? 22) * scaleFactor,
        height: 1.3,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: (baseTextTheme.titleMedium?.fontSize ?? 16) * scaleFactor,
        height: 1.3,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: (baseTextTheme.titleSmall?.fontSize ?? 14) * scaleFactor,
        height: 1.3,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: (baseTextTheme.bodyLarge?.fontSize ?? 16) * scaleFactor,
        height: 1.4,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: (baseTextTheme.bodyMedium?.fontSize ?? 14) * scaleFactor,
        height: 1.4,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: (baseTextTheme.bodySmall?.fontSize ?? 12) * scaleFactor,
        height: 1.4,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: (baseTextTheme.labelLarge?.fontSize ?? 14) * scaleFactor,
        height: 1.3,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: (baseTextTheme.labelMedium?.fontSize ?? 12) * scaleFactor,
        height: 1.3,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: (baseTextTheme.labelSmall?.fontSize ?? 11) * scaleFactor,
        height: 1.3,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme.copyWith(
        primary: AppBrand.primaryColor,
        onPrimary: AppBrand.onPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppBrand.primaryColor,
        foregroundColor: AppBrand.onPrimary,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppBrand.onPrimary,
        unselectedLabelColor: AppBrand.onPrimaryMuted,
        indicatorColor: AppBrand.onPrimary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(Colors.white10),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppBrand.primaryColor,
          foregroundColor: AppBrand.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF323232),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        actionTextColor: AppBrand.primaryColor,
      ),
    );
  }

  /// Creates a dark theme with the given locale's font.
  static ThemeData darkTheme(AppLocale locale) {
    final fontFamily = fontFamilyFor(locale);
    final scaleFactor = urdu_text.UrduTextScaler.getScaleFactor(locale);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppBrand.primaryColor,
      secondary: AppBrand.secondaryColor,
      error: AppBrand.errorColor,
      brightness: Brightness.dark,
    );

    // Build scaled text theme for RTL languages
    final baseTextTheme =
        ThemeData(fontFamily: fontFamily, brightness: Brightness.dark)
            .textTheme;
    final textTheme = TextTheme(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: (baseTextTheme.displayLarge?.fontSize ?? 57) * scaleFactor,
        height: 1.2,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: (baseTextTheme.displayMedium?.fontSize ?? 45) * scaleFactor,
        height: 1.2,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: (baseTextTheme.displaySmall?.fontSize ?? 36) * scaleFactor,
        height: 1.3,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: (baseTextTheme.headlineLarge?.fontSize ?? 32) * scaleFactor,
        height: 1.3,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: (baseTextTheme.headlineMedium?.fontSize ?? 28) * scaleFactor,
        height: 1.3,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: (baseTextTheme.headlineSmall?.fontSize ?? 24) * scaleFactor,
        height: 1.3,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: (baseTextTheme.titleLarge?.fontSize ?? 22) * scaleFactor,
        height: 1.3,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: (baseTextTheme.titleMedium?.fontSize ?? 16) * scaleFactor,
        height: 1.3,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: (baseTextTheme.titleSmall?.fontSize ?? 14) * scaleFactor,
        height: 1.3,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: (baseTextTheme.bodyLarge?.fontSize ?? 16) * scaleFactor,
        height: 1.4,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: (baseTextTheme.bodyMedium?.fontSize ?? 14) * scaleFactor,
        height: 1.4,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: (baseTextTheme.bodySmall?.fontSize ?? 12) * scaleFactor,
        height: 1.4,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: (baseTextTheme.labelLarge?.fontSize ?? 14) * scaleFactor,
        height: 1.3,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: (baseTextTheme.labelMedium?.fontSize ?? 12) * scaleFactor,
        height: 1.3,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: (baseTextTheme.labelSmall?.fontSize ?? 11) * scaleFactor,
        height: 1.3,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme.copyWith(
        primary: AppBrand.primaryColor,
        onPrimary: AppBrand.onPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppBrand.primaryColor,
        foregroundColor: AppBrand.onPrimary,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppBrand.onPrimary,
        unselectedLabelColor: AppBrand.onPrimaryMuted,
        indicatorColor: AppBrand.onPrimary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(Colors.white10),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppBrand.primaryColor,
          foregroundColor: AppBrand.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF424242),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        actionTextColor: AppBrand.primaryColor,
      ),
    );
  }

  // ─── Semantic colour helpers ──────────────────────────────────────────────
  // Use these throughout the UI to avoid hardcoded light-only shade50/shade700
  // pairs that break in dark mode.  They resolve to M3 container colours which
  // Flutter generates correct dark-mode variants for automatically.

  /// Red / debt / error container background.
  static Color debtBg(ColorScheme cs) => cs.errorContainer;

  /// Text / icon colour on top of [debtBg].
  static Color debtFg(ColorScheme cs) => cs.onErrorContainer;

  /// Green / clear / success container background.
  static Color clearBg(ColorScheme cs) => cs.tertiaryContainer;

  /// Text / icon colour on top of [clearBg].
  static Color clearFg(ColorScheme cs) => cs.onTertiaryContainer;

  /// Orange / warning container background.
  static Color warningBg(ColorScheme cs) => cs.secondaryContainer;

  /// Text / icon colour on top of [warningBg].
  static Color warningFg(ColorScheme cs) => cs.onSecondaryContainer;

  // Legacy getters kept for backward compatibility
  static ThemeData get light => lightTheme(AppLocale.en);
  static ThemeData get dark => darkTheme(AppLocale.en);

  // Status chip colours
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'complete':
      case 'delivered':
      case 'approved':
      case 'paid':
      case 'qc_passed':
        return AppBrand.successColor;
      case 'pending':
      case 'draft':
      case 'in_production':
      case 'qc_pending':
      case 'pending_approval':
        return AppBrand.warningColor;
      case 'rejected':
      case 'cancelled':
      case 'qc_issues':
      case 'stock_issue':
        return AppBrand.errorColor;
      case 'processing':
      case 'reserved':
      case 'shipped':
      case 'sent':
      case 'in_transit':
      case 'assigned_to_seller':
        return AppBrand.primaryColor;
      case 'ready_for_shipment':
        return Colors.indigo;
      case 'received':
        return AppBrand.successColor;
      default:
        return Colors.grey;
    }
  }
}
