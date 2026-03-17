import 'package:flutter/material.dart';
import '../constants/app_brand.dart';
import '../l10n/app_locale.dart';

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

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppBrand.primaryColor,
      secondary: AppBrand.secondaryColor,
      error: AppBrand.errorColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme.copyWith(
        primary: AppBrand.primaryColor,
        onPrimary: AppBrand.onPrimary,
      ),
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
    );
  }

  /// Creates a dark theme with the given locale's font.
  static ThemeData darkTheme(AppLocale locale) {
    final fontFamily = fontFamilyFor(locale);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppBrand.primaryColor,
      secondary: AppBrand.secondaryColor,
      error: AppBrand.errorColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
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
    );
  }

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
        return AppBrand.primaryColor;
      default:
        return Colors.grey;
    }
  }
}
