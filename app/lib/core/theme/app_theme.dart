import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_brand.dart';
import '../design/app_tokens.dart';
import '../l10n/app_locale.dart';
import '../theme/app_fonts.dart';
import '../../providers/theme_preference_provider.dart';

class AppTheme {
  AppTheme._();

  // ── Semantic colours exposed for widgets ─────────────────────────────────
  static const Color success = AppBrand.successColor;
  static const Color warning = AppBrand.warningColor;

  // ═══════════════════════════════════════════════════════════════════════════
  //  ARCTIC COLOR PALETTE
  // ═══════════════════════════════════════════════════════════════════════════
  static const Color seedColor = Color(0xFF00D4FF);

  // ── Dark Mode Colors (deep navy arctic feel) ──
  static const Color arcticBlue = Color(0xFF00D4FF);
  static const Color arcticDarkBg = Color(0xFF0A0E1A);
  static const Color arcticSurface = Color(0xFF111827);
  static const Color arcticCard = Color(0xFF1A2332);
  static const Color arcticSuccess = Color(0xFF00E676);
  static const Color arcticError = Color(0xFFFF5252);
  static const Color arcticWarning = Color(0xFFFFAB40);
  static const Color arcticPending = Color(0xFFFFD740);
  static const Color arcticTextPrimary = Color(0xFFE2E8F0);
  static const Color arcticTextSecondary = Color(0xFF94A3B8);
  static const Color arcticDivider = Color(0xFF1E293B);
  static const Color arcticBlueDark = Color(0xFF0099CC);

  // ── Light Mode Colors (clean, airy, professional) ──
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF1E293B);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightDivider = Color(0xFFE2E8F0);
  static const Color lightBlue = Color(0xFF0284C7);
  static const Color lightSuccess = Color(0xFF16A34A);
  static const Color lightError = Color(0xFFDC2626);
  static const Color lightWarning = Color(0xFFD97706);
  static const Color lightPending = Color(0xFFF59E0B);

  // ── High Contrast Colors (vivid neon-on-black, maximum readability) ──
  static const Color hcBg = Color(0xFF000000);
  static const Color hcSurface = Color(0xFF0D0D0D);
  static const Color hcCard = Color(0xFF0D0D0D);
  static const Color hcTextPrimary = Color(0xFFFFFFFF);
  static const Color hcTextSecondary = Color(0xFFE0E0E0);
  static const Color hcDivider = Color(0xFFFFD600);
  static const Color hcBlue = Color(0xFF00FFFF);
  static const Color hcSuccess = Color(0xFF00FF7F);
  static const Color hcError = Color(0xFFFF1744);
  static const Color hcWarning = Color(0xFFFFD600);
  static const Color hcPending = Color(0xFFFFD600);

  // ═══════════════════════════════════════════════════════════════════════════
  //  THEME FACTORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns the correct theme for the current mode + locale.
  static ThemeData themeForMode(
    AppThemeMode mode,
    AppLocale locale, {
    Brightness systemBrightness = Brightness.dark,
  }) {
    final loc = locale.locale.languageCode;
    return switch (mode) {
      AppThemeMode.auto =>
        systemBrightness == Brightness.light
            ? lightThemeForLocale(loc)
            : darkThemeForLocale(loc),
      AppThemeMode.dark => darkThemeForLocale(loc),
      AppThemeMode.light => lightThemeForLocale(loc),
      AppThemeMode.highContrast => highContrastThemeForLocale(loc),
    };
  }

  /// Returns the effective [Brightness] for the given mode, used by
  /// MaterialApp to resolve `theme` vs `darkTheme`.
  static Brightness brightnessForMode(
    AppThemeMode mode,
    Brightness systemBrightness,
  ) {
    return switch (mode) {
      AppThemeMode.auto => systemBrightness,
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.highContrast => Brightness.dark,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DARK THEME
  // ═══════════════════════════════════════════════════════════════════════════
  static ThemeData darkThemeForLocale(String locale) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      surface: arcticSurface,
    ).copyWith(primary: arcticBlue, error: arcticError);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: arcticDarkBg,
      textTheme: AppFonts.textTheme(
        locale,
        textPrimary: arcticTextPrimary,
        textSecondary: arcticTextSecondary,
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: arcticDarkBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: AppFonts.heading(
          locale,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: arcticTextPrimary,
        ),
        iconTheme: const IconThemeData(color: arcticBlue),
        actionsIconTheme: const IconThemeData(color: arcticBlue),
        surfaceTintColor: Colors.transparent,
      ),

      // ── Card ──
      cardTheme: CardThemeData(
        color: arcticCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(
          horizontal: AppTokens.s16,
          vertical: 6,
        ),
      ),

      // ── Buttons ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: arcticBlue,
          foregroundColor: arcticDarkBg,
          elevation: 2,
          shadowColor: arcticBlue.withAlpha(80),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s24,
            vertical: 14,
          ),
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: AppFonts.body(
            locale,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: arcticBlue,
          foregroundColor: arcticDarkBg,
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: AppFonts.body(
            locale,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: arcticBlue,
          side: const BorderSide(color: arcticBlue),
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: AppFonts.body(
            locale,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: arcticBlue,
          textStyle: AppFonts.body(
            locale,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Input ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: arcticCard,
        hintStyle: AppFonts.body(
          locale,
          fontSize: 14,
          color: arcticTextSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: arcticBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: arcticError, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      // ── Navigation Bar ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: arcticSurface,
        indicatorColor: arcticBlue.withAlpha(38),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: arcticBlue);
          }
          return const IconThemeData(color: arcticTextSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppFonts.body(
              locale,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: arcticBlue,
            );
          }
          return AppFonts.body(
            locale,
            fontSize: 12,
            color: arcticTextSecondary,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        height: 64,
        surfaceTintColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // ── Navigation Rail ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: arcticSurface,
        indicatorShape: RoundedRectangleBorder(borderRadius: AppTokens.brMD),
        indicatorColor: arcticBlue.withAlpha(38),
        selectedIconTheme: const IconThemeData(color: arcticBlue),
        unselectedIconTheme: const IconThemeData(color: arcticTextSecondary),
        selectedLabelTextStyle: AppFonts.body(
          locale,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: arcticBlue,
        ),
        unselectedLabelTextStyle: AppFonts.body(
          locale,
          fontSize: 12,
          color: arcticTextSecondary,
        ),
        labelType: NavigationRailLabelType.all,
      ),

      // ── Tab Bar ──
      tabBarTheme: TabBarThemeData(
        labelColor: arcticBlue,
        unselectedLabelColor: arcticTextSecondary,
        indicatorColor: arcticBlue,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: AppFonts.body(
          locale,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppFonts.body(locale, fontSize: 14),
        dividerColor: arcticDivider,
      ),

      // ── Dialog / Sheet ──
      dialogTheme: DialogThemeData(
        backgroundColor: arcticSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXL),
        ),
        elevation: 6,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: arcticSurface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXL),
          ),
        ),
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: arcticCard,
        selectedColor: arcticBlue.withAlpha(51),
        labelStyle: AppFonts.body(
          locale,
          fontSize: 13,
          color: arcticTextPrimary,
        ),
        secondaryLabelStyle: AppFonts.body(
          locale,
          fontSize: 13,
          color: arcticBlue,
        ),
        side: const BorderSide(color: arcticDivider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      // ── Snack Bar ──
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brMD),
        backgroundColor: arcticCard,
        contentTextStyle: AppFonts.body(locale, color: arcticTextPrimary),
        actionTextColor: arcticBlue,
      ),

      // ── List Tile ──
      listTileTheme: ListTileThemeData(
        iconColor: arcticTextSecondary,
        textColor: arcticTextPrimary,
        subtitleTextStyle: AppFonts.body(
          locale,
          fontSize: 13,
          color: arcticTextSecondary,
        ),
        selectedTileColor: arcticBlue.withAlpha(32),
        selectedColor: arcticBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(color: arcticDivider, thickness: 1),

      // ── FAB ──
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: arcticBlue,
        foregroundColor: arcticDarkBg,
        elevation: 4,
      ),

      // ── Date Picker ──
      datePickerTheme: DatePickerThemeData(
        backgroundColor: arcticSurface,
        headerBackgroundColor: arcticCard,
        headerForegroundColor: arcticBlue,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return arcticDarkBg;
          return arcticTextPrimary;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return arcticBlue;
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.all(arcticBlue),
        todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        todayBorder: const BorderSide(color: arcticBlue),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return arcticBlue;
          return arcticTextSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return arcticBlue.withAlpha(77);
          }
          return arcticDivider;
        }),
      ),

      // ── Checkbox ──
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return arcticBlue;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(arcticDarkBg),
        side: const BorderSide(color: arcticTextSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // ── Text Selection ──
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: arcticBlue,
        selectionColor: Color(0x5500D4FF),
        selectionHandleColor: arcticBlue,
      ),

      // ── Popup Menu ──
      popupMenuTheme: PopupMenuThemeData(
        color: arcticCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        textStyle: AppFonts.body(locale, fontSize: 13, color: arcticDarkBg),
        decoration: BoxDecoration(
          color: arcticBlue,
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // ── Progress Indicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: arcticBlue,
        linearTrackColor: arcticDivider,
        circularTrackColor: arcticDivider,
      ),

      // ── Badge ──
      badgeTheme: const BadgeThemeData(
        backgroundColor: arcticError,
        textColor: Colors.white,
      ),

      // ── Icon Button ──
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: arcticTextPrimary),
      ),

      // ── Dropdown Menu ──
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: arcticCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: arcticDivider),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LIGHT THEME
  // ═══════════════════════════════════════════════════════════════════════════
  static ThemeData lightThemeForLocale(String locale) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: lightBlue,
          brightness: Brightness.light,
          surface: lightSurface,
        ).copyWith(
          primary: lightBlue,
          error: lightError,
          onSurface: lightTextPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: lightBg,
      textTheme: AppFonts.textTheme(
        locale,
        textPrimary: lightTextPrimary,
        textSecondary: lightTextSecondary,
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: lightBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: AppFonts.heading(
          locale,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        surfaceTintColor: Colors.transparent,
      ),

      // ── Card ──
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 2,
        shadowColor: Colors.black26,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightDivider),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: AppTokens.s16,
          vertical: 6,
        ),
      ),

      // ── Buttons ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: lightBlue.withAlpha(80),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s24,
            vertical: 14,
          ),
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: AppFonts.body(
            locale,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: lightBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: AppFonts.body(
            locale,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightBlue,
          side: const BorderSide(color: lightBlue),
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: AppFonts.body(
            locale,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightBlue,
          textStyle: AppFonts.body(
            locale,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Input ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightCard,
        hintStyle: AppFonts.body(
          locale,
          fontSize: 14,
          color: lightTextSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightDivider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightError, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      // ── Navigation Bar ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSurface,
        indicatorColor: lightBlue.withAlpha(31),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: lightBlue);
          }
          return const IconThemeData(color: lightTextSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppFonts.body(
              locale,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: lightBlue,
            );
          }
          return AppFonts.body(locale, fontSize: 12, color: lightTextSecondary);
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 2,
        height: 64,
        surfaceTintColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // ── Navigation Rail ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: lightSurface,
        indicatorShape: RoundedRectangleBorder(borderRadius: AppTokens.brMD),
        indicatorColor: lightBlue.withAlpha(22),
        selectedIconTheme: const IconThemeData(color: lightBlue),
        unselectedIconTheme: const IconThemeData(color: lightTextSecondary),
        selectedLabelTextStyle: AppFonts.body(
          locale,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: lightBlue,
        ),
        unselectedLabelTextStyle: AppFonts.body(
          locale,
          fontSize: 12,
          color: lightTextSecondary,
        ),
        labelType: NavigationRailLabelType.all,
      ),

      // ── Tab Bar ──
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: AppFonts.body(
          locale,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppFonts.body(locale, fontSize: 14),
        dividerColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.white10),
      ),

      // ── Dialog / Sheet ──
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXL),
        ),
        elevation: 6,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXL),
          ),
        ),
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: lightSurface,
        selectedColor: lightBlue.withAlpha(31),
        labelStyle: AppFonts.body(
          locale,
          fontSize: 13,
          color: lightTextPrimary,
        ),
        secondaryLabelStyle: AppFonts.body(
          locale,
          fontSize: 13,
          color: lightBlue,
        ),
        side: const BorderSide(color: lightDivider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      // ── Snack Bar ──
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brMD),
        backgroundColor: lightCard,
        contentTextStyle: AppFonts.body(locale, color: lightTextPrimary),
        actionTextColor: lightBlue,
      ),

      // ── List Tile ──
      listTileTheme: ListTileThemeData(
        iconColor: lightTextSecondary,
        textColor: lightTextPrimary,
        subtitleTextStyle: AppFonts.body(
          locale,
          fontSize: 13,
          color: lightTextSecondary,
        ),
        selectedTileColor: lightBlue.withAlpha(18),
        selectedColor: lightBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(color: lightDivider, thickness: 1),

      // ── FAB ──
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: lightBlue,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      // ── Date Picker ──
      datePickerTheme: DatePickerThemeData(
        backgroundColor: lightSurface,
        headerBackgroundColor: lightBlue,
        headerForegroundColor: Colors.white,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return lightTextPrimary;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return lightBlue;
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.all(lightBlue),
        todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        todayBorder: const BorderSide(color: lightBlue),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return lightBlue;
          return lightTextSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return lightBlue.withAlpha(77);
          }
          return lightDivider;
        }),
      ),

      // ── Checkbox ──
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return lightBlue;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: lightTextSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // ── Text Selection ──
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: lightBlue,
        selectionColor: Color(0x330284C7),
        selectionHandleColor: lightBlue,
      ),

      // ── Popup Menu ──
      popupMenuTheme: PopupMenuThemeData(
        color: lightCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        textStyle: AppFonts.body(locale, fontSize: 13, color: Colors.white),
        decoration: BoxDecoration(
          color: lightTextPrimary,
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // ── Progress Indicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: lightBlue,
        linearTrackColor: lightDivider,
        circularTrackColor: lightDivider,
      ),

      // ── Badge ──
      badgeTheme: const BadgeThemeData(
        backgroundColor: lightError,
        textColor: Colors.white,
      ),

      // ── Icon Button ──
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: lightTextPrimary),
      ),

      // ── Dropdown Menu ──
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: lightCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: lightDivider),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  HIGH CONTRAST THEME
  // ═══════════════════════════════════════════════════════════════════════════
  static ThemeData highContrastThemeForLocale(String locale) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: hcBlue,
      brightness: Brightness.dark,
      surface: hcSurface,
    ).copyWith(primary: hcBlue, error: hcError, onSurface: hcTextPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: hcBg,
      textTheme: AppFonts.textTheme(
        locale,
        textPrimary: hcTextPrimary,
        textSecondary: hcTextSecondary,
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: hcSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppFonts.heading(
          locale,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: hcBlue,
        ),
        iconTheme: const IconThemeData(color: hcBlue, size: 28),
        actionsIconTheme: const IconThemeData(color: hcBlue, size: 28),
        surfaceTintColor: Colors.transparent,
      ),

      // ── Card ──
      cardTheme: CardThemeData(
        color: hcCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: hcDivider, width: 2),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: AppTokens.s16,
          vertical: 6,
        ),
      ),

      // ── Buttons ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: hcBlue,
          foregroundColor: hcBg,
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: hcBlue, width: 2),
          ),
          textStyle: AppFonts.body(
            locale,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: hcBlue,
          foregroundColor: hcBg,
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: hcBlue, width: 2),
          ),
          textStyle: AppFonts.body(
            locale,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: hcBlue,
          side: const BorderSide(color: hcBlue, width: 2),
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: AppFonts.body(
            locale,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: hcBlue,
          textStyle: AppFonts.body(
            locale,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // ── Input ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: hcCard,
        hintStyle: AppFonts.body(locale, fontSize: 14, color: hcTextSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: hcDivider, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: hcDivider, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: hcBlue, width: 3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: hcError, width: 3),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      // ── Navigation Bar ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: hcSurface,
        indicatorColor: hcBlue.withAlpha(64),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: hcBlue, size: 28);
          }
          return const IconThemeData(color: hcTextSecondary, size: 28);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppFonts.body(
              locale,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: hcBlue,
            );
          }
          return AppFonts.body(locale, fontSize: 12, color: hcTextSecondary);
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        height: 64,
        surfaceTintColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // ── Navigation Rail ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: hcSurface,
        indicatorShape: RoundedRectangleBorder(borderRadius: AppTokens.brMD),
        indicatorColor: hcBlue.withAlpha(64),
        selectedIconTheme: const IconThemeData(color: hcBlue, size: 28),
        unselectedIconTheme: const IconThemeData(
          color: hcTextSecondary,
          size: 28,
        ),
        selectedLabelTextStyle: AppFonts.body(
          locale,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: hcBlue,
        ),
        unselectedLabelTextStyle: AppFonts.body(
          locale,
          fontSize: 12,
          color: hcTextSecondary,
        ),
        labelType: NavigationRailLabelType.all,
      ),

      // ── Tab Bar ──
      tabBarTheme: TabBarThemeData(
        labelColor: hcBlue,
        unselectedLabelColor: hcTextSecondary,
        indicatorColor: hcBlue,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: AppFonts.body(
          locale,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: AppFonts.body(locale, fontSize: 14),
        dividerColor: hcDivider,
      ),

      // ── Dialog / Sheet ──
      dialogTheme: DialogThemeData(
        backgroundColor: hcSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXL),
          side: const BorderSide(color: hcDivider, width: 2),
        ),
        elevation: 6,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: hcSurface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXL),
          ),
        ),
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: hcCard,
        selectedColor: hcBlue.withAlpha(77),
        labelStyle: AppFonts.body(locale, fontSize: 14, color: hcTextPrimary),
        secondaryLabelStyle: AppFonts.body(locale, fontSize: 14, color: hcBlue),
        side: const BorderSide(color: hcDivider, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      // ── Snack Bar ──
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.brMD,
          side: const BorderSide(color: hcDivider, width: 2),
        ),
        backgroundColor: hcCard,
        contentTextStyle: AppFonts.body(locale, color: hcTextPrimary),
        actionTextColor: hcBlue,
      ),

      // ── List Tile ──
      listTileTheme: ListTileThemeData(
        iconColor: hcTextSecondary,
        textColor: hcTextPrimary,
        subtitleTextStyle: AppFonts.body(
          locale,
          fontSize: 13,
          color: hcTextSecondary,
        ),
        selectedTileColor: hcBlue.withAlpha(51),
        selectedColor: hcBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(color: hcDivider, thickness: 2),

      // ── FAB ──
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: hcBlue,
        foregroundColor: hcBg,
        elevation: 0,
      ),

      // ── Date Picker ──
      datePickerTheme: DatePickerThemeData(
        backgroundColor: hcSurface,
        headerBackgroundColor: hcCard,
        headerForegroundColor: hcBlue,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return hcBg;
          return hcTextPrimary;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return hcBlue;
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.all(hcBlue),
        todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        todayBorder: const BorderSide(color: hcBlue, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return hcBlue;
          return hcTextSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return hcBlue.withAlpha(128);
          }
          return hcSurface;
        }),
        trackOutlineColor: WidgetStateProperty.all(hcDivider),
      ),

      // ── Checkbox ──
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return hcBlue;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(hcBg),
        side: const BorderSide(color: hcDivider, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // ── Text Selection ──
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: hcBlue,
        selectionColor: Color(0x5500FFFF),
        selectionHandleColor: hcBlue,
      ),

      // ── Popup Menu ──
      popupMenuTheme: PopupMenuThemeData(
        color: hcCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: hcDivider, width: 2),
        ),
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        textStyle: AppFonts.body(locale, fontSize: 14, color: hcBg),
        decoration: BoxDecoration(
          color: hcBlue,
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // ── Progress Indicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: hcBlue,
        linearTrackColor: hcDivider,
        circularTrackColor: hcDivider,
      ),

      // ── Badge ──
      badgeTheme: const BadgeThemeData(
        backgroundColor: hcError,
        textColor: hcBg,
      ),

      // ── Icon Button ──
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: hcTextPrimary),
      ),

      // ── Dropdown Menu ──
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: hcCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: hcDivider, width: 2),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BACKWARD-COMPATIBLE API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Creates a light theme with the given locale's font.
  static ThemeData lightTheme(AppLocale locale) =>
      lightThemeForLocale(locale.locale.languageCode);

  /// Creates a dark theme with the given locale's font.
  static ThemeData darkTheme(AppLocale locale) =>
      darkThemeForLocale(locale.locale.languageCode);

  // Legacy getters kept for backward compatibility
  static ThemeData get light => lightThemeForLocale('en');
  static ThemeData get dark => darkThemeForLocale('en');

  // ═══════════════════════════════════════════════════════════════════════════
  //  SEMANTIC COLOUR HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════════════════
  //  MODE-AWARE COLOR HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static Color cardColor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.auto || AppThemeMode.dark => arcticCard,
    AppThemeMode.light => lightCard,
    AppThemeMode.highContrast => hcCard,
  };

  static Color bgColor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.auto || AppThemeMode.dark => arcticDarkBg,
    AppThemeMode.light => lightBg,
    AppThemeMode.highContrast => hcBg,
  };

  static Color primaryColor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.auto || AppThemeMode.dark => arcticBlue,
    AppThemeMode.light => lightBlue,
    AppThemeMode.highContrast => hcBlue,
  };

  static Color successResolvedColor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.auto || AppThemeMode.dark => arcticSuccess,
    AppThemeMode.light => lightSuccess,
    AppThemeMode.highContrast => hcSuccess,
  };

  static Color errorResolvedColor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.auto || AppThemeMode.dark => arcticError,
    AppThemeMode.light => lightError,
    AppThemeMode.highContrast => hcError,
  };

  static Color warningResolvedColor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.auto || AppThemeMode.dark => arcticWarning,
    AppThemeMode.light => lightWarning,
    AppThemeMode.highContrast => hcWarning,
  };

  static Color textPrimaryColor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.auto || AppThemeMode.dark => arcticTextPrimary,
    AppThemeMode.light => lightTextPrimary,
    AppThemeMode.highContrast => hcTextPrimary,
  };

  static Color textSecondaryColor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.auto || AppThemeMode.dark => arcticTextSecondary,
    AppThemeMode.light => lightTextSecondary,
    AppThemeMode.highContrast => hcTextSecondary,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  STATUS CHIP COLOURS
  // ═══════════════════════════════════════════════════════════════════════════
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
