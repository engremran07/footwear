import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/auth_refresh_policy.dart';

void main() {
  test('network and transient failures retain the authenticated session', () {
    expect(
      shouldSignOutAfterAuthRefreshFailure('network-request-failed'),
      isFalse,
    );
    expect(shouldSignOutAfterAuthRefreshFailure('too-many-requests'), isFalse);
    expect(shouldSignOutAfterAuthRefreshFailure('unknown'), isFalse);
  });

  test('terminal account and token failures sign out', () {
    expect(shouldSignOutAfterAuthRefreshFailure('user-disabled'), isTrue);
    expect(shouldSignOutAfterAuthRefreshFailure('user-token-expired'), isTrue);
    expect(shouldSignOutAfterAuthRefreshFailure('user-not-found'), isTrue);
    expect(shouldSignOutAfterAuthRefreshFailure('invalid-user-token'), isTrue);
  });
}
