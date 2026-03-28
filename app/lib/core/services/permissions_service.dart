import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Requests runtime permissions once on first app launch.
/// Subsequent launches skip silently.
class PermissionsService {
  static const _keyFirstRun = 'permissions_requested_v1';

  static Future<void> requestOnFirstRun() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyFirstRun) == true) return;
      await [
        Permission.camera,
        Permission.photos, // READ_MEDIA_IMAGES on Android 13+
        Permission.storage, // READ/WRITE_EXTERNAL_STORAGE on Android ≤12
        Permission.notification, // POST_NOTIFICATIONS on Android 13+
      ].request();
      await prefs.setBool(_keyFirstRun, true);
    } catch (e) {
      debugPrint('PermissionsService: $e');
    }
  }
}
