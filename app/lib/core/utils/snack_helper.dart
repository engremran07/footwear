import 'package:flutter/material.dart';
import '../constants/app_brand.dart';

/// Convenience helpers for uniform snack bar messages across the app.

/// Returns a styled error SnackBar widget for use with ScaffoldMessenger.
SnackBar errorSnackBar(String msg) => _styledSnackBar(
  msg: msg,
  bg: AppBrand.errorBg,
  fg: AppBrand.errorFg,
  accent: AppBrand.errorAccent,
  icon: Icons.error_rounded,
  duration: const Duration(seconds: 4),
);

/// Returns a styled success SnackBar widget for use with ScaffoldMessenger.
SnackBar successSnackBar(String msg) => _styledSnackBar(
  msg: msg,
  bg: AppBrand.successBg,
  fg: AppBrand.successFg,
  accent: AppBrand.successAccent,
  icon: Icons.check_circle_rounded,
);

/// Returns a styled warning SnackBar widget for use with ScaffoldMessenger.
SnackBar warningSnackBar(String msg) => _styledSnackBar(
  msg: msg,
  bg: AppBrand.warningBg,
  fg: AppBrand.warningFg,
  accent: AppBrand.warningAccent,
  icon: Icons.warning_rounded,
  duration: const Duration(seconds: 4),
);

/// Returns a styled info SnackBar widget for use with ScaffoldMessenger.
SnackBar infoSnackBar(String msg) => _styledSnackBar(
  msg: msg,
  bg: AppBrand.infoBg,
  fg: AppBrand.infoFg,
  accent: AppBrand.infoAccent,
  icon: Icons.info_rounded,
);

SnackBar _styledSnackBar({
  required String msg,
  required Color bg,
  required Color fg,
  required Color accent,
  required IconData icon,
  Duration duration = const Duration(seconds: 3),
}) {
  return SnackBar(
    content: Row(
      children: [
        Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, color: fg, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            msg,
            style: TextStyle(
              color: fg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
    backgroundColor: bg,
    behavior: SnackBarBehavior.floating,
    elevation: 4,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: accent.withValues(alpha: 0.3)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    duration: duration,
  );
}

void showSuccess(BuildContext ctx, String msg) {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    _styledSnackBar(
      msg: msg,
      bg: AppBrand.successBg,
      fg: AppBrand.successFg,
      accent: AppBrand.successAccent,
      icon: Icons.check_circle_rounded,
    ),
  );
}

void showError(BuildContext ctx, String msg) {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    _styledSnackBar(
      msg: msg,
      bg: AppBrand.errorBg,
      fg: AppBrand.errorFg,
      accent: AppBrand.errorAccent,
      icon: Icons.error_rounded,
      duration: const Duration(seconds: 4),
    ),
  );
}

void showInfo(BuildContext ctx, String msg) {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    _styledSnackBar(
      msg: msg,
      bg: AppBrand.infoBg,
      fg: AppBrand.infoFg,
      accent: AppBrand.infoAccent,
      icon: Icons.info_rounded,
    ),
  );
}
