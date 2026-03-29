import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    // Keep auth sessions clean across account switches by disabling disk cache.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );

    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(rememberMePrefKey) ?? true;
    if (!rememberMe && FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    } else if (rememberMe && FirebaseAuth.instance.currentUser != null) {
      // Force token refresh so Firestore queries don't fail with stale token
      try {
        await FirebaseAuth.instance.currentUser!.getIdToken(true);
      } catch (_) {
        // Token refresh failed (offline/expired) — force re-login
        await FirebaseAuth.instance.signOut();
      }
    }
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  runApp(const ProviderScope(child: FootwearErpApp()));
}
