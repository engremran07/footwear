import 'package:flutter/material.dart';
import '../constants/app_brand.dart';
import '../design/app_tokens.dart';
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

  // ─── Safe font-size scaler (avoids assert when fontSize is null) ────────
  static TextTheme _safeScaleTextTheme(
      TextTheme base, double factor, String? family) {
    // When factor is 1.0 and no family override, return as-is
    if (factor == 1.0 && family == null) return base;

    TextStyle scale(TextStyle? style) {
      if (style == null) return const TextStyle();
      final scaled = style.copyWith(
        fontSize: (style.fontSize ?? 14.0) * factor,
      );
      return family != null ? scaled.copyWith(fontFamily: family) : scaled;
    }

    return TextTheme(
      displayLarge: scale(base.displayLarge),
      displayMedium: scale(base.displayMedium),
      displaySmall: scale(base.displaySmall),
      headlineLarge: scale(base.headlineLarge),
      headlineMedium: scale(base.headlineMedium),
      headlineSmall: scale(base.headlineSmall),
      titleLarge: scale(base.titleLarge),
      titleMedium: scale(base.titleMedium),
      titleSmall: scale(base.titleSmall),
      bodyLarge: scale(base.bodyLarge),
      bodyMedium: scale(base.bodyMedium),
      bodySmall: scale(base.bodySmall),
      labelLarge: scale(base.labelLarge),
      labelMedium: scale(base.labelMedium),
      labelSmall: scale(base.labelSmall),
    );
  }

  // ─── DRY theme builder ────────────────────────────────────────────────────
  static ThemeData _buildTheme(Brightness brightness, AppLocale locale) {
    final fontFamily = fontFamilyFor(locale);
    final scaleFactor = urdu_text.UrduTextScaler.getScaleFactor(locale);
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppBrand.primaryColor,
      secondary: AppBrand.secondaryColor,
      error: AppBrand.errorColor,
      brightness: brightness,
    ).copyWith(
      primary: AppBrand.primaryColor,
      onPrimary: AppBrand.onPrimary,
    );

    // Scaled text theme — safe against null fontSize in any style
    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final textTheme =
        _safeScaleTextTheme(baseTextTheme, scaleFactor, fontFamily);

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: isDark ? colorScheme.surface : AppBrand.primaryColor,
        foregroundColor: isDark ? colorScheme.onSurface : AppBrand.onPrimary,
        surfaceTintColor: isDark ? colorScheme.surfaceTint : null,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppBrand.onPrimary,
        unselectedLabelColor: AppBrand.onPrimaryMuted,
        indicatorColor: AppBrand.onPrimary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(Colors.white10),
      ),
      navigationRailTheme: NavigationRailThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: AppTokens.brMD,
        ),
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        labelType: NavigationRailLabelType.all,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: AppTokens.brMD,
        ),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXL),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXL),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: AppTokens.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.brMD,
        ),
        margin:
            const EdgeInsets.symmetric(horizontal: AppTokens.s16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: AppTokens.brSM),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s16, vertical: AppTokens.s12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppBrand.primaryColor,
          foregroundColor: AppBrand.onPrimary,
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s24, vertical: 14),
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(borderRadius: AppTokens.brSM),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(borderRadius: AppTokens.brSM),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brMD),
        backgroundColor:
            isDark ? const Color(0xFF424242) : const Color(0xFF323232),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        actionTextColor: AppBrand.primaryColor,
      ),
    );
  }

  /// Creates a light theme with the given locale's font.
  static ThemeData lightTheme(AppLocale locale) =>
      _buildTheme(Brightness.light, locale);

  /// Creates a dark theme with the given locale's font.
  static ThemeData darkTheme(AppLocale locale) =>
      _buildTheme(Brightness.dark, locale);

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
