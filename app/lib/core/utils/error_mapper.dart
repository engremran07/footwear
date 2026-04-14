import 'package:firebase_auth/firebase_auth.dart';

/// Maps Firebase and Dart exceptions to user-friendly i18n translation keys.
/// All keys must exist in app_locale.dart for EN / AR / UR.
class AppErrorMapper {
  AppErrorMapper._();

  static bool isPermissionOrAuthError(Object error) {
    final mappedKey = key(error);
    return mappedKey == 'err_permission_denied' ||
        mappedKey == 'err_unauthenticated';
  }

  /// Returns a locale key for the given error object.
  static String key(Object error) {
    // ── Firebase Auth errors ───────────────────────────────────────────
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'INVALID_LOGIN_CREDENTIALS' => 'err_invalid_credentials',
        'user-not-found' => 'err_user_not_found',
        'user-disabled' => 'err_user_disabled',
        'too-many-requests' => 'err_too_many_requests',
        'email-already-in-use' => 'err_email_in_use',
        'weak-password' => 'err_weak_password',
        'invalid-email' => 'err_invalid_email',
        'network-request-failed' => 'err_network',
        'operation-not-allowed' => 'err_operation_not_allowed',
        'requires-recent-login' => 'err_requires_recent_login',
        _ => 'err_auth_generic',
      };
    }
    // ── Firebase Storage + Firestore errors ───────────────────────────
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' || 'unauthorized' => 'err_permission_denied',
        'not-found' || 'object-not-found' => 'err_not_found',
        'already-exists' => 'err_already_exists',
        'resource-exhausted' || 'quota-exceeded' => 'err_resource_exhausted',
        'unavailable' || 'retry-limit-exceeded' => 'err_service_unavailable',
        'cancelled' => 'err_cancelled',
        'deadline-exceeded' => 'err_timeout',
        'unauthenticated' => 'err_unauthenticated',
        'failed-precondition' => 'err_index_missing',
        _ => 'err_firebase_generic',
      };
    }

    // ── Dart built-in errors ───────────────────────────────────────────
    final msg = error.toString().toLowerCase();
    if (msg.contains('route_has_seller')) return 'route_has_seller';
    if (msg.contains('route_has_shops')) return 'route_has_shops';
    if (msg.contains('no user found')) return 'err_user_not_found';
    if (msg.contains('not authenticated') ||
        msg.contains('sellerid must not be empty') ||
        msg.contains('seller_id must not be empty')) {
      return 'err_unauthenticated';
    }
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return 'err_network';
    }
    if (msg.contains('timeout')) return 'err_timeout';
    if (msg.contains('format')) return 'err_invalid_data';
    if (msg.contains('no data') || msg.contains('no records')) {
      return 'err_export_no_data';
    }
    if (msg.contains('pdf') || msg.contains('export failed')) {
      return 'err_pdf_failed';
    }

    return 'err_unknown';
  }
}
