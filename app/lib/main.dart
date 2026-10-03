import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/l10n/app_locale.dart';
import 'firebase_options.dart';
import 'core/utils/auth_refresh_policy.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseInitialized = false;

  // Edge-to-edge: draw behind system bars so zoom drawer fills full screen
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseInitialized = true;

    // Crashlytics has no web implementation; avoid unhandled platform calls.
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }

    // S-06: App Check is opt-in for release Android APKs.
    // Default remains sideload-friendly unless USE_PLAY_INTEGRITY=true is set.
    const usePlayIntegrity = bool.fromEnvironment(
      'USE_PLAY_INTEGRITY',
      defaultValue: false,
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (kDebugMode) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidDebugProvider(),
        );
      } else if (usePlayIntegrity) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidPlayIntegrityProvider(),
        );
      }
    }

    // Enable Firestore offline persistence for faster loads
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(rememberMePrefKey) ?? true;
    if (!rememberMe && FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
    // Defer token refresh to after first frame to avoid blocking startup.
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  if (!firebaseInitialized) {
    runApp(const ProviderScope(child: _FirebaseInitializationFailureApp()));
    return;
  }

  runApp(const ProviderScope(child: FootwearErpApp()));

  // Post-first-frame: refresh token if user is remembered.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _deferredTokenRefresh();
  });
}

class _FirebaseInitializationFailureApp extends ConsumerWidget {
  const _FirebaseInitializationFailureApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 44,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    tr('err_firebase_init_title', ref),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('err_firebase_init_body', ref),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      main();
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text(tr('retry', ref)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _deferredTokenRefresh() async {
  final bool rememberMe;
  try {
    final prefs = await SharedPreferences.getInstance();
    rememberMe = prefs.getBool(rememberMePrefKey) ?? true;
  } catch (e, stack) {
    if (!kIsWeb) FirebaseCrashlytics.instance.recordError(e, stack);
    return;
  }
  if (!rememberMe) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    await user.getIdToken(true);
  } on FirebaseAuthException catch (e, stack) {
    if (shouldSignOutAfterAuthRefreshFailure(e.code)) {
      await FirebaseAuth.instance.signOut();
    } else if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(e, stack);
    }
  } catch (e, stack) {
    if (!kIsWeb) FirebaseCrashlytics.instance.recordError(e, stack);
  }
}
