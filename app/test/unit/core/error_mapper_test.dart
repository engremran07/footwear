import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/error_mapper.dart';

void main() {
  group('AppErrorMapper.key — FirebaseAuthException', () {
    test('wrong-password → err_invalid_credentials', () {
      final e = FirebaseAuthException(code: 'wrong-password');
      expect(AppErrorMapper.key(e), equals('err_invalid_credentials'));
    });

    test('invalid-credential → err_invalid_credentials', () {
      final e = FirebaseAuthException(code: 'invalid-credential');
      expect(AppErrorMapper.key(e), equals('err_invalid_credentials'));
    });

    test('user-not-found → err_user_not_found', () {
      final e = FirebaseAuthException(code: 'user-not-found');
      expect(AppErrorMapper.key(e), equals('err_user_not_found'));
    });

    test('user-disabled → err_user_disabled', () {
      final e = FirebaseAuthException(code: 'user-disabled');
      expect(AppErrorMapper.key(e), equals('err_user_disabled'));
    });

    test('too-many-requests → err_too_many_requests', () {
      final e = FirebaseAuthException(code: 'too-many-requests');
      expect(AppErrorMapper.key(e), equals('err_too_many_requests'));
    });

    test('email-already-in-use → err_email_in_use', () {
      final e = FirebaseAuthException(code: 'email-already-in-use');
      expect(AppErrorMapper.key(e), equals('err_email_in_use'));
    });

    test('weak-password → err_weak_password', () {
      final e = FirebaseAuthException(code: 'weak-password');
      expect(AppErrorMapper.key(e), equals('err_weak_password'));
    });

    test('network-request-failed → err_network', () {
      final e = FirebaseAuthException(code: 'network-request-failed');
      expect(AppErrorMapper.key(e), equals('err_network'));
    });

    test('requires-recent-login → err_requires_recent_login', () {
      final e = FirebaseAuthException(code: 'requires-recent-login');
      expect(AppErrorMapper.key(e), equals('err_requires_recent_login'));
    });

    test('unknown code → err_auth_generic', () {
      final e = FirebaseAuthException(code: 'some-unknown-code');
      expect(AppErrorMapper.key(e), equals('err_auth_generic'));
    });
  });

  group('AppErrorMapper.key — FirebaseException (Firestore)', () {
    test('permission-denied → err_permission_denied', () {
      final e = FirebaseException(
        plugin: 'firestore',
        code: 'permission-denied',
      );
      expect(AppErrorMapper.key(e), equals('err_permission_denied'));
    });

    test('not-found → err_not_found', () {
      final e = FirebaseException(plugin: 'firestore', code: 'not-found');
      expect(AppErrorMapper.key(e), equals('err_not_found'));
    });

    test('already-exists → err_already_exists', () {
      final e = FirebaseException(plugin: 'firestore', code: 'already-exists');
      expect(AppErrorMapper.key(e), equals('err_already_exists'));
    });

    test('resource-exhausted → err_resource_exhausted', () {
      final e = FirebaseException(
        plugin: 'firestore',
        code: 'resource-exhausted',
      );
      expect(AppErrorMapper.key(e), equals('err_resource_exhausted'));
    });

    test('unavailable → err_service_unavailable', () {
      final e = FirebaseException(plugin: 'firestore', code: 'unavailable');
      expect(AppErrorMapper.key(e), equals('err_service_unavailable'));
    });

    test('cancelled → err_cancelled', () {
      final e = FirebaseException(plugin: 'firestore', code: 'cancelled');
      expect(AppErrorMapper.key(e), equals('err_cancelled'));
    });

    test('unauthenticated → err_unauthenticated', () {
      final e = FirebaseException(plugin: 'firestore', code: 'unauthenticated');
      expect(AppErrorMapper.key(e), equals('err_unauthenticated'));
    });

    test('unknown code → err_firebase_generic', () {
      final e = FirebaseException(plugin: 'firestore', code: 'banana');
      expect(AppErrorMapper.key(e), equals('err_firebase_generic'));
    });
  });

  group('AppErrorMapper.key — plain Dart errors', () {
    test('exception containing "socket" → err_network', () {
      expect(
        AppErrorMapper.key(Exception('socket closed')),
        equals('err_network'),
      );
    });

    test('exception containing "timeout" → err_timeout', () {
      expect(
        AppErrorMapper.key(Exception('timeout exceeded')),
        equals('err_timeout'),
      );
    });

    test('exception containing "format" → err_invalid_data', () {
      expect(
        AppErrorMapper.key(Exception('format error')),
        equals('err_invalid_data'),
      );
    });

    test('exception containing "no user found" → err_user_not_found', () {
      expect(
        AppErrorMapper.key(Exception('No user found with that email')),
        equals('err_user_not_found'),
      );
    });

    test('StateError "Not authenticated" → err_unauthenticated', () {
      expect(
        AppErrorMapper.key(StateError('Not authenticated')),
        equals('err_unauthenticated'),
      );
    });

    test(
      'ArgumentError "sellerId must not be empty" → err_unauthenticated',
      () {
        expect(
          AppErrorMapper.key(ArgumentError('sellerId must not be empty')),
          equals('err_unauthenticated'),
        );
      },
    );

    test('unrecognised exception → err_unknown', () {
      expect(
        AppErrorMapper.key(Exception('something completely random xyz')),
        equals('err_unknown'),
      );
    });
  });

  group('AppErrorMapper.isPermissionOrAuthError', () {
    test('permission-denied error returns true', () {
      final e = FirebaseException(
        plugin: 'firestore',
        code: 'permission-denied',
      );
      expect(AppErrorMapper.isPermissionOrAuthError(e), isTrue);
    });

    test('unauthenticated auth error returns true', () {
      final e = FirebaseException(plugin: 'firestore', code: 'unauthenticated');
      expect(AppErrorMapper.isPermissionOrAuthError(e), isTrue);
    });

    test('network error returns false', () {
      final e = FirebaseAuthException(code: 'network-request-failed');
      expect(AppErrorMapper.isPermissionOrAuthError(e), isFalse);
    });
  });
}
