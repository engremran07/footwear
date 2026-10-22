import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/auth_refresh_policy.dart';

void main() {
  test('network and transient failures retain authenticated state', () {
    expect(
      shouldSignOutAfterAuthRefreshFailure('network-request-failed'),
      isFalse,
    );
    expect(shouldSignOutAfterAuthRefreshFailure('too-many-requests'), isFalse);
    expect(shouldSignOutAfterAuthRefreshFailure('unknown'), isFalse);
  });

  test('terminal account and token failures sign out', () {
    expect(shouldSignOutAfterAuthRefreshFailure('user-disabled'), isTrue);
    expect(shouldSignOutAfterAuthRefreshFailure('user-token-expired'), isFalse);
    expect(shouldSignOutAfterAuthRefreshFailure('user-not-found'), isTrue);
    expect(shouldSignOutAfterAuthRefreshFailure('invalid-user-token'), isTrue);
  });

  test('only credential errors contribute to login lockout', () {
    expect(isCredentialSignInFailure('invalid-credential'), isTrue);
    expect(isCredentialSignInFailure('WRONG-PASSWORD'), isTrue);
    expect(isCredentialSignInFailure('permission-denied'), isFalse);
    expect(isCredentialSignInFailure('network-request-failed'), isFalse);
  });
}
