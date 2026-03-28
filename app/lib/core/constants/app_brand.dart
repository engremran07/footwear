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
  static const String appVersion = '2.0.0';
  static const String buildNumber = '6';
  static const String versionDisplay = 'v$appVersion+$buildNumber';

  // ─── Contact / About ─────────────────────────────────────────────────────
  static const String contactEmail = 'support@footwear-erp.com';
  static const String contactPhone = '+966 50 000 0000';
  static const String websiteUrl = 'https://footwear-erp.com';
  static const String aboutDescription =
      'FootWear is a comprehensive enterprise resource planning system '
      'designed for footwear distribution businesses in Saudi Arabia. '
      'It manages inventory, orders, payroll, quality control, '
      'and financial reporting for KSA warehouse operations.';

  // ─── Palette (edit to rebrand) ───────────────────────────────────────────
  static const Color primaryColor = Color(0xFF1565C0); // deep blue
  static const Color secondaryColor = Color(0xFF00897B); // teal
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color warningColor = Color(0xFFF57C00);
  static const Color successColor = Color(0xFF388E3C);
  static const Color stockColor = Color(0xFF5D4037); // brown — warehouse/stock
  static const Color adminRoleColor = Color(0xFF6A1B9A); // deep purple
  static const Color sellerRoleColor =
      Color(0xFF00897B); // teal — same as secondary

  // ─── Semantic helpers ────────────────────────────────────────────────────
  static const Color onPrimary = Colors.white;
  static const Color onPrimaryMuted = Colors.white70;

  // ─── Typography ──────────────────────────────────────────────────────────
  static const String fontFamilyUrdu = 'NotoNastaliqUrdu';
  static const String fontFamilyArabic = 'NotoSansArabic';
}
