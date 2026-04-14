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
import 'firebase_options.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

    // S-01: Crashlytics — collect in release only
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

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
    } else if (rememberMe && FirebaseAuth.instance.currentUser != null) {
      try {
        await FirebaseAuth.instance.currentUser!.getIdToken(true);
      } catch (e, stack) {
        // S-01: Log token refresh failure to Crashlytics before sign-out
        FirebaseCrashlytics.instance.recordError(e, stack);
        await FirebaseAuth.instance.signOut();
      }
    }
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  runApp(const ProviderScope(child: FootwearErpApp()));
}
