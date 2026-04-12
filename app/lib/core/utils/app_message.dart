import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_brand.dart';
import '../l10n/app_locale.dart';
import 'error_mapper.dart';

/// Centralised, themed message service used across the entire app.
///
/// Usage:
///   AppMessage.success(context, ref, 'saved_successfully');
///   AppMessage.error(context, ref, error);
///   AppMessage.info(context, ref, 'some_info_key');
///   AppMessage.warning(context, ref, 'some_warning_key');
class AppMessage {
  AppMessage._();

  // ── Duration constants ──────────────────────────────────────────────
  static const _shortDuration = Duration(seconds: 2);
  static const _normalDuration = Duration(seconds: 3);
  static const _longDuration = Duration(seconds: 5);

  // ── Public API ──────────────────────────────────────────────────────

  /// Show a green success snackbar with a translated message key.
  static void success(BuildContext context, WidgetRef ref, String key) {
    _show(context, ref, key, _Type.success);
  }

  /// Show a red error snackbar. Accepts an [Object] error and maps it
  /// via [AppErrorMapper] to a user-friendly i18n key automatically.
  static void error(BuildContext context, WidgetRef ref, Object error) {
    final key = AppErrorMapper.key(error);
    _show(context, ref, key, _Type.error, duration: _longDuration);
  }

  /// Show a red error snackbar with a specific i18n key.
  static void errorKey(BuildContext context, WidgetRef ref, String key) {
    _show(context, ref, key, _Type.error);
  }

  /// Show a blue info snackbar.
  static void info(BuildContext context, WidgetRef ref, String key) {
    _show(context, ref, key, _Type.info);
  }

  /// Show an amber warning snackbar.
  static void warning(BuildContext context, WidgetRef ref, String key) {
    _show(context, ref, key, _Type.warning);
  }

  // ── Internal ────────────────────────────────────────────────────────

  static void _show(
    BuildContext context,
    WidgetRef ref,
    String key,
    _Type type, {
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();

    final text = tr(key, ref);

    final (Color bg, Color fg, Color accent, IconData icon) = switch (type) {
      _Type.success => (
        AppBrand.successBg,
        AppBrand.successFg,
        AppBrand.successAccent,
        Icons.check_circle_rounded,
      ),
      _Type.error => (
        AppBrand.errorBg,
        AppBrand.errorFg,
        AppBrand.errorAccent,
        Icons.error_rounded,
      ),
      _Type.warning => (
        AppBrand.warningBg,
        AppBrand.warningFg,
        AppBrand.warningAccent,
        Icons.warning_rounded,
      ),
      _Type.info => (
        AppBrand.infoBg,
        AppBrand.infoFg,
        AppBrand.infoAccent,
        Icons.info_rounded,
      ),
    };

    messenger.showSnackBar(
      SnackBar(
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
                text,
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
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        duration:
            duration ??
            (type == _Type.error ? _normalDuration : _shortDuration),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }
}

enum _Type { success, error, warning, info }
