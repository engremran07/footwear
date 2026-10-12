bool shouldSignOutAfterAuthRefreshFailure(String code) => const {
  'invalid-user-token',
  'user-disabled',
  'user-not-found',
}.contains(code);

bool isCredentialSignInFailure(String code) => const {
  'invalid-credential',
  'invalid-login-credentials',
  'wrong-password',
}.contains(code.toLowerCase());
