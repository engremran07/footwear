import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/constants/app_brand.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    // Cap Firestore cache at 100 MB to prevent slow cold starts
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024,
    );
    // Version-gated cache flush: clears stale offline data when the app updates.
    final prefs = await SharedPreferences.getInstance();
    const currentBuild = AppBrand.buildNumber;
    final storedBuild = prefs.getString('app_build') ?? '';
    if (storedBuild != currentBuild) {
      try {
        await FirebaseFirestore.instance.clearPersistence();
      } catch (_) {}
      await prefs.setString('app_build', currentBuild);
    }
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  runApp(const ProviderScope(child: FootwearErpApp()));
}
