import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import '../constants/collections.dart';

/// Provides full admin-level Firebase Auth operations directly from the app
/// without Cloud Functions — 100% Spark free-tier compatible.
///
/// 4-Way Sync Chain:
///   1. AdminIdentityService.updateAuthUser()  → Firebase Auth (email/pw/verified)
///   2. UserManagementNotifier.adminUpdateUserAuth() → Firestore users/{uid}
///   3. Riverpod allUsersProvider / authUserProvider → auto-stream on Firestore change
///   4. Flutter UI → re-renders automatically from Riverpod state
///
/// How it works:
///   1. Read SA key JSON from admin_config/sa_credentials (Firestore, admin-only)
///   2. Build a RS256-signed JWT (iss=SA email, aud=token endpoint, scope=firebase)
///   3. POST to https://oauth2.googleapis.com/token → get OAuth2 access token
///   4. Call Identity Toolkit Admin REST API with the access token
///
/// Security model:
///   - admin_config is locked to admin reads only via Firestore rules
///   - Seller accounts can NEVER read admin_config
///   - OAuth2 tokens are ephemeral (55-min cache, cleared on sign-out)
///   - SA key is never logged or written to local storage
///
/// Free-tier note: On Blaze upgrade, this can be migrated to Cloud Functions
/// + Firebase Admin SDK for an extra security layer.
class AdminIdentityService {
  AdminIdentityService._();
  static final AdminIdentityService instance = AdminIdentityService._();

  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _itBase = 'https://identitytoolkit.googleapis.com/v1';
  // cloud-platform covers accounts:update AND projects.accounts.sendOobCode.
  // The narrower "firebase" scope covers only accounts:update and triggers
  // "insufficient request scope" on the project-scoped sendOobCode endpoint.
  static const _scope = 'https://www.googleapis.com/auth/cloud-platform';
  static const _projectId = 'shoeserp-clean-20260327';
  // Firebase Web API key — used only for the custom-token → ID-token exchange
  // (public value, safe to embed; it is not the SA private key).
  static const _apiKey = 'AIzaSyBkuhoehQ8G7GBCx5Gun_v3KOlM2gqyBDg';
  static const Duration _requestTimeout = Duration(seconds: 20);

  // OAuth2 token cache — valid 55 min (actual SA token lasts 60 min).
  // Scope embedded so a change to _scope automatically invalidates old cache.
  String? _cachedToken;
  DateTime? _tokenExpiry;
  String? _cachedScope; // tracks which scope the cached token was issued for

  // SA credentials cache — immutable after first load, cleared on sign-out.
  Map<String, dynamic>? _cachedCreds;

  // ── SA credential loading ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> _getOrLoadCreds() async {
    if (_cachedCreds != null) return _cachedCreds!;
    final snap = await FirebaseFirestore.instance
        .collection(Collections.adminConfig)
        .doc('sa_credentials')
        .get();
    if (!snap.exists || snap.data() == null) {
      throw Exception(
        'SA credentials not provisioned. '
        'Run the setup script to populate admin_config/sa_credentials.',
      );
    }
    final b64 = snap.data()!['sa_json_b64'] as String;
    _cachedCreds =
        jsonDecode(utf8.decode(base64.decode(b64))) as Map<String, dynamic>;
    return _cachedCreds!;
  }

  // ── JWT + OAuth2 exchange ─────────────────────────────────────────────────

  Future<String> _getAccessToken() async {
    // Return cached token if still valid AND issued under the same scope
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        _cachedScope == _scope &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedToken!;
    }

    final creds = await _getOrLoadCreds();
    final clientEmail = creds['client_email'] as String;
    // Google SA JSON stores newlines as literal \n — unescape them
    final privateKeyPem = (creds['private_key'] as String).replaceAll(
      r'\n',
      '\n',
    );

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final jwt = JWT({
      'iss': clientEmail,
      'sub': clientEmail,
      'aud': _tokenEndpoint,
      'iat': nowSec,
      'exp': nowSec + 3600,
      'scope': _scope,
    });

    final token = jwt.sign(
      RSAPrivateKey(privateKeyPem),
      algorithm: JWTAlgorithm.RS256,
    );

    final response = await http
        .post(
          Uri.parse(_tokenEndpoint),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion': token,
          },
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'OAuth2 token exchange failed [${response.statusCode}]: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _cachedToken = data['access_token'] as String;
    _tokenExpiry = DateTime.now().add(const Duration(minutes: 55));
    _cachedScope = _scope;
    return _cachedToken!;
  }

  /// Clear all in-memory caches — call this on admin sign-out.
  void clearCache() {
    _cachedToken = null;
    _tokenExpiry = null;
    _cachedScope = null;
    _cachedCreds = null;
  }

  // ── Auth operations ───────────────────────────────────────────────────────

  /// Update [email], [password], and/or [emailVerified] for any user by [uid].
  /// Uses Identity Toolkit Admin REST API (requires SA OAuth2 token).
  Future<void> updateAuthUser({
    required String uid,
    String? email,
    String? password,
    bool? emailVerified,
  }) async {
    final accessToken = await _getAccessToken();

    final body = <String, dynamic>{'localId': uid};
    if (email != null && email.trim().isNotEmpty) {
      body['email'] = email.trim().toLowerCase();
    }
    if (password != null && password.isNotEmpty) {
      body['password'] = password;
    }
    if (emailVerified != null) {
      body['emailVerified'] = emailVerified;
    }

    final response = await http
        .post(
          Uri.parse('$_itBase/projects/$_projectId/accounts:update'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body) as Map<String, dynamic>;
      final msg = (err['error']?['message'] as String?) ?? response.body;
      throw Exception(msg);
    }
  }

  /// Send a verification email for [uid] / [email].
  ///
  /// VERIFY_EMAIL always requires a real user idToken — admin SA bearer alone
  /// is rejected with "INVALID_ID_TOKEN". Correct 3-step flow:
  ///   1. Mint a Firebase custom token for the target UID (RS256, SA private key)
  ///   2. Exchange custom token → ephemeral ID token (signInWithCustomToken)
  ///   3. Use that ID token in sendOobCode (no admin bearer needed for this step)
  Future<void> sendVerificationEmail(String uid, String email) async {
    final creds = await _getOrLoadCreds();
    final clientEmail = creds['client_email'] as String;
    final privateKeyPem = (creds['private_key'] as String).replaceAll(
      r'\n',
      '\n',
    );

    // ── Step 1: mint Firebase custom token for target UID ──────────────────
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final customJwt = JWT({
      'iss': clientEmail,
      'sub': clientEmail,
      'aud':
          'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
      'iat': nowSec,
      'exp': nowSec + 3600,
      'uid': uid,
    });
    final customToken = customJwt.sign(
      RSAPrivateKey(privateKeyPem),
      algorithm: JWTAlgorithm.RS256,
    );

    // ── Step 2: exchange custom token → ephemeral ID token ─────────────────
    final signInResp = await http
        .post(
          Uri.parse('$_itBase/accounts:signInWithCustomToken?key=$_apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': customToken, 'returnSecureToken': true}),
        )
        .timeout(_requestTimeout);
    if (signInResp.statusCode != 200) {
      final err = jsonDecode(signInResp.body) as Map<String, dynamic>;
      throw Exception((err['error']?['message'] as String?) ?? signInResp.body);
    }
    final idToken =
        (jsonDecode(signInResp.body) as Map<String, dynamic>)['idToken']
            as String;

    // ── Step 3: send verification email with the user's own ID token ────────
    final oobResp = await http
        .post(
          Uri.parse('$_itBase/accounts:sendOobCode?key=$_apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'requestType': 'VERIFY_EMAIL', 'idToken': idToken}),
        )
        .timeout(_requestTimeout);
    if (oobResp.statusCode != 200) {
      final err = jsonDecode(oobResp.body) as Map<String, dynamic>;
      final msg = (err['error']?['message'] as String?) ?? oobResp.body;
      throw Exception(msg);
    }
  }

  /// Send a password reset email to [email].
  /// PASSWORD_RESET only needs the email — no idToken required.
  Future<void> sendPasswordResetEmail(String email) async {
    // Use the public accounts:sendOobCode endpoint (no admin token needed
    // for PASSWORD_RESET — it accepts just the email + API key).
    final response = await http
        .post(
          Uri.parse('$_itBase/accounts:sendOobCode?key=$_apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'requestType': 'PASSWORD_RESET',
            'email': email.trim().toLowerCase(),
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body) as Map<String, dynamic>;
      final msg = (err['error']?['message'] as String?) ?? response.body;
      throw Exception(msg);
    }
  }
}
