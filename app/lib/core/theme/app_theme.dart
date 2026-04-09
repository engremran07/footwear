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

    // ── Arctic M3 Color Scheme ─────────────────────────────────────────────
    // ColorScheme.fromSeed with Arctic Sky Blue seed generates the full tonal
    // palette; we then override specific roles for Arctic-brand alignment.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppBrand.arcticSeedColor,
      brightness: brightness,
    ).copyWith(
      // Override primary to the deeper glacier blue (avoids M3 auto-brightening)
      primary: isDark ? const Color(0xFF81D4FA) : AppBrand.primaryColor,
      onPrimary: isDark ? const Color(0xFF003549) : AppBrand.onPrimary,
      // Arctic surface tones: slightly icy white (light), polar night (dark)
      surface: isDark ? const Color(0xFF0D1618) : const Color(0xFFF2FAFD),
      onSurface: isDark ? const Color(0xFFDCF0F8) : const Color(0xFF001F2A),
      surfaceContainerHighest:
          isDark ? const Color(0xFF1A2D35) : const Color(0xFFD6EEF8),
      surfaceContainer:
          isDark ? const Color(0xFF121F25) : const Color(0xFFE4F3FA),
    );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final textTheme =
        _safeScaleTextTheme(baseTextTheme, scaleFactor, fontFamily);

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      // Scaffold background matches the surface tint exactly
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,

      // ── AppBar ────────────────────────────────────────────────────────────
      // backgroundColor intentionally solid (not transparent) so screen-level
      // AppBars get the Arctic primary colour by default.
      // The shell AppBar overrides this per-widget with a gradient flexibleSpace.
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor:
            isDark ? const Color(0xFF001825) : AppBrand.primaryColor,
        foregroundColor: AppBrand.onPrimary,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppBrand.onPrimary, size: 24),
        actionsIconTheme: const IconThemeData(color: AppBrand.onPrimary),
      ),

      // ── Bottom Navigation Bar ─────────────────────────────────────────────
      // The custom _ArcticBottomNav in app_shell.dart draws its own surface.
      // These tokens are used by screen-level NavigationBars if any.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF0D1618) : colorScheme.surface,
        indicatorColor: isDark
            ? const Color(0xFF003D56)
            : AppBrand.primaryColor.withAlpha(30),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
                color:
                    isDark ? const Color(0xFF81D4FA) : AppBrand.primaryColor);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final baseColor = states.contains(WidgetState.selected)
              ? (isDark ? const Color(0xFF81D4FA) : AppBrand.primaryColor)
              : colorScheme.onSurfaceVariant;
          return TextStyle(
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.normal,
            color: baseColor,
          );
        }),
        overlayColor:
            WidgetStatePropertyAll(AppBrand.primaryColor.withAlpha(15)),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // ── Navigation Rail ────────────────────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor:
            isDark ? const Color(0xFF0D1618) : const Color(0xFFE8F5FD),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: AppTokens.brMD,
        ),
        indicatorColor: isDark
            ? const Color(0xFF003D56)
            : AppBrand.primaryColor.withAlpha(22),
        selectedIconTheme: IconThemeData(
          color: isDark ? const Color(0xFF81D4FA) : AppBrand.primaryColor,
        ),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: isDark ? const Color(0xFF81D4FA) : AppBrand.primaryColor,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
        labelType: NavigationRailLabelType.all,
      ),

      // ── Tab Bar ────────────────────────────────────────────────────────────
      tabBarTheme: const TabBarThemeData(
        labelColor: AppBrand.onPrimary,
        unselectedLabelColor: AppBrand.onPrimaryMuted,
        indicatorColor: AppBrand.onPrimary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(Colors.white10),
      ),

      // ── Dialog / Sheet ────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF0D2030) : colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXL),
        ),
        elevation: 6,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF0D2030) : colorScheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXL),
          ),
        ),
      ),

      // ── Card ──────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        // Arctic cards: barely-tinted surface with subtle icy shadow
        color: isDark ? const Color(0xFF121F25) : const Color(0xFFEAF5FB),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.brMD,
          side: BorderSide(
            color: isDark ? const Color(0xFF1E3340) : const Color(0xFFB6DFF0),
            width: 1,
          ),
        ),
        margin:
            const EdgeInsets.symmetric(horizontal: AppTokens.s16, vertical: 6),
        shadowColor: AppBrand.primaryColor.withAlpha(20),
      ),

      // ── Input ─────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF172530)
            : const Color(0xFFE3F2FD).withAlpha(200),
        border: OutlineInputBorder(
          borderRadius: AppTokens.brSM,
          borderSide: BorderSide(color: colorScheme.outline.withAlpha(100)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppTokens.brSM,
          borderSide: BorderSide(
              color:
                  isDark ? const Color(0xFF1E3A50) : const Color(0xFFB0D8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppTokens.brSM,
          borderSide: BorderSide(
              color: isDark ? const Color(0xFF81D4FA) : AppBrand.primaryColor,
              width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s16, vertical: AppTokens.s12),
      ),

      // ── Buttons ───────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppBrand.primaryColor,
          foregroundColor: AppBrand.onPrimary,
          elevation: 2,
          shadowColor: AppBrand.primaryColor.withAlpha(80),
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor:
              isDark ? const Color(0xFF81D4FA) : AppBrand.primaryColor,
          side: BorderSide(
              color: isDark ? const Color(0xFF81D4FA) : AppBrand.primaryColor),
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(borderRadius: AppTokens.brSM),
        ),
      ),

      // ── Chip ─────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? const Color(0xFF172530) : const Color(0xFFE1F5FE),
        selectedColor: isDark
            ? const Color(0xFF003D56)
            : AppBrand.primaryColor.withAlpha(30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark ? const Color(0xFF1E3A50) : const Color(0xFFB0D8F0),
          ),
        ),
      ),

      // ── Snack Bar ─────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brMD),
        backgroundColor:
            isDark ? const Color(0xFF1A3040) : const Color(0xFF00344A),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        actionTextColor: const Color(0xFF81D4FA),
      ),

      // ── List Tile ─────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        selectedTileColor: isDark
            ? AppBrand.primaryColor.withAlpha(32)
            : AppBrand.primaryColor.withAlpha(18),
        selectedColor: isDark ? const Color(0xFF81D4FA) : AppBrand.primaryColor,
        iconColor: colorScheme.onSurfaceVariant,
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF1E3340) : const Color(0xFFB6DFF0),
        thickness: 0.8,
      ),

      // ── FloatingActionButton ───────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor:
            isDark ? const Color(0xFF003D56) : AppBrand.primaryColor,
        foregroundColor: AppBrand.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brLG),
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
      case 'issued':
        return AppBrand.primaryColor;
      case 'partial':
        return AppBrand.warningColor;
      case 'void':
        return AppBrand.errorColor;
      case 'credit_note':
        return AppBrand.successColor;
      case 'ready_for_shipment':
        return AppBrand.primaryColor;
      case 'received':
        return AppBrand.successColor;
      default:
        return AppBrand.secondaryColor;
    }
  }
}
