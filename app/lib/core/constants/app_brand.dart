import 'package:flutter/material.dart';

/// Centralized branding config — edit here to white-label the app.
/// All screens, widgets, and the theme read from this single source.
class AppBrand {
  AppBrand._();

  // ─── Identity ────────────────────────────────────────────────────────────
  static const String appName = 'FootWear';
  static const String companyName = 'FootWear';
  static const IconData logoIcon = Icons.work_outline;
  static const String logoAsset = 'assets/images/app_icon.png';

  // ─── Version ─────────────────────────────────────────────────────────────
  static const String appVersion = '3.7.5';
  static const String buildNumber = '53';
  static const String versionDisplay = 'v$appVersion+$buildNumber';

  // ─── Contact / About ─────────────────────────────────────────────────────
  static const String contactEmail = 'engremran89@gmail.com';
  static const String contactPhonePrimary = '+923067863310';
  static const String contactPhoneSecondary = '+966530421571';
  static const String websiteUrl = 'https://shoeserp-clean-20260327.web.app/';
  static const String aboutDescription =
      'FootWear is a comprehensive enterprise resource planning system '
      'designed for footwear distribution businesses in Saudi Arabia. '
      'It manages inventory, orders, payroll, quality control, '
      'and financial reporting for KSA warehouse operations.';

  // ─── Arctic Palette ──────────────────────────────────────────────────────
  // Seed drives Material 3 tone generation; override specific roles below.
  static const Color arcticSeedColor = Color(0xFF0288D1); // Arctic Sky Blue

  static const Color primaryColor = Color(0xFF01579B); // Glacier Deep Blue
  static const Color secondaryColor = Color(0xFF37474F); // Arctic Slate Rock
  static const Color tertiaryColor = Color(
    0xFF5C5FBE,
  ); // Northern Lights Indigo
  static const Color errorColor = Color(0xFFBA1A1A); // Ice Alert Red
  static const Color warningColor = Color(0xFFE07C00); // Arctic Flame
  static const Color successColor = Color(0xFF2E7D32); // Glacier Pine
  static const Color stockColor = Color(0xFF455A64); // Arctic Steel
  static const Color adminRoleColor = Color(0xFF5C5FBE); // Aurora Indigo
  static const Color sellerRoleColor = Color(0xFF01579B); // Glacier Blue

  // ─── Arctic Gradients ─────────────────────────────────────────────────────
  /// AppBar gradient — deep glacier left, arctic sky right (light mode).
  static const LinearGradient appBarGradientLight = LinearGradient(
    colors: [Color(0xFF01579B), Color(0xFF0288D1)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// AppBar gradient — polar night (dark mode).
  static const LinearGradient appBarGradientDark = LinearGradient(
    colors: [Color(0xFF001825), Color(0xFF002D3F)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Drawer header gradient — polar depths to glacier (both modes).
  static const LinearGradient drawerHeaderGradient = LinearGradient(
    colors: [Color(0xFF003D56), Color(0xFF0277BD)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Subtle aurora accent line (AppBar bottom border glow).
  static const LinearGradient auroraAccent = LinearGradient(
    colors: [Color(0xFF26C6DA), Color(0xFF7C4DFF), Color(0xFF00E5FF)],
    stops: [0.0, 0.5, 1.0],
  );

  // ─── Semantic helpers ────────────────────────────────────────────────────
  static const Color onPrimary = Colors.white;
  static const Color onPrimaryMuted = Colors.white70;

  // ─── Snack bar container colours (Arctic-tinted) ─────────────────────────
  static const Color errorBg = Color(0xFFFCEEEB); // ice rose
  static const Color errorFg = Color(0xFF8C1D18); // deep crimson
  static const Color errorAccent = Color(0xFFBA1A1A);
  static const Color successBg = Color(0xFFEBF5EE); // frost mint
  static const Color successFg = Color(0xFF1B5E20); // glacier pine
  static const Color successAccent = Color(0xFF2E7D32);
  static const Color warningBg = Color(0xFFFFF3E0); // arctic amber
  static const Color warningFg = Color(0xFF7D3E00);
  static const Color warningAccent = Color(0xFFE07C00);
  static const Color infoBg = Color(0xFFE1F5FE); // ice blue
  static const Color infoFg = Color(0xFF01579B); // glacier deep
  static const Color infoAccent = Color(0xFF0288D1);

  // ─── Typography ──────────────────────────────────────────────────────────
  static const String fontFamilyUrdu = 'NotoNastaliqUrdu';
  static const String fontFamilyArabic = 'NotoSansArabic';
}
