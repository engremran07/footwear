bool shouldSignOutAfterAuthRefreshFailure(String code) => const {
  'invalid-user-token',
  'user-disabled',
  'user-not-found',
  'user-token-expired',
}.contains(code);
