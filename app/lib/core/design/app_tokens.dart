import 'package:flutter/material.dart';

/// Centralised design tokens — replaces magic numbers throughout the app.
/// Based on 8pt grid, Material 3 conventions.
class AppTokens {
  AppTokens._();

  // ─── Spacing (8pt base grid) ───
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;

  // ─── Border Radius ───
  static const double rXS = 4;
  static const double rSM = 8;
  static const double rMD = 12;
  static const double rLG = 16;
  static const double rXL = 24;
  static const double rFull = 100;

  static final BorderRadius brXS = BorderRadius.circular(rXS);
  static final BorderRadius brSM = BorderRadius.circular(rSM);
  static final BorderRadius brMD = BorderRadius.circular(rMD);
  static final BorderRadius brLG = BorderRadius.circular(rLG);
  static final BorderRadius brXL = BorderRadius.circular(rXL);
  static final BorderRadius brFull = BorderRadius.circular(rFull);

  // ─── Elevation / Shadows (Arctic blue-tinted depth) ───
  static const List<BoxShadow> shadowSM = [
    BoxShadow(color: Color(0x0C0277BD), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadowMD = [
    BoxShadow(color: Color(0x180277BD), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x080277BD), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadowLG = [
    BoxShadow(color: Color(0x220277BD), blurRadius: 16, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0C0277BD), blurRadius: 6, offset: Offset(0, 2)),
  ];

  // ─── Motion Durations ───
  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durNormal = Duration(milliseconds: 250);
  static const Duration durSlow = Duration(milliseconds: 400);
  static const Duration durPage = Duration(milliseconds: 300);

  /// Arctic-slow — for glacial fade and premium entrances
  static const Duration durGlacial = Duration(milliseconds: 600);

  /// Used for staggered list items in large screens (80ms per step)
  static const Duration durStaggerStep = Duration(milliseconds: 80);

  // ─── Motion Curves ───
  static const Curve curveStd = Curves.easeInOut;
  static const Curve curveEnter = Curves.easeOut;
  static const Curve curveExit = Curves.easeIn;
  static const Curve curveSpring = Curves.elasticOut;
  static const Curve curveDecel = Curves.decelerate;

  // ─── Component sizes ───
  static const double buttonMinHeight = 48;
  static const double iconSizeSM = 18;
  static const double iconSizeMD = 24;
  static const double iconSizeLG = 32;
  static const double avatarRadius = 20;
  static const double dialogMaxWidth = 400;
  static const double formMaxWidth = 600;
  static const double cardElevation = 1;

  // ─── Breakpoints ───
  static const double breakpointMobile = 600;
  static const double breakpointTablet = 900;
  static const double breakpointDesktop = 1200;
}
