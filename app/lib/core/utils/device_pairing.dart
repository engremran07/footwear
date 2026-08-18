import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DevicePairing {
  const DevicePairing._();

  static const String _storageKey = 'device_pairing.device_id';

  static String sanitize(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  static Future<String> currentDeviceIdentifier() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_storageKey)?.trim();
      if (existing != null && existing.isNotEmpty) {
        return sanitize(existing);
      }
      final generated = const Uuid().v4();
      await prefs.setString(_storageKey, generated);
      return sanitize(generated);
    }

    final os = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    final host = Platform.localHostname;
    final base = '$os:$version:$host';
    return sanitize(base);
  }

  static bool matches(String? expected, String? actual) {
    final expectedValue = sanitize(expected);
    final actualValue = sanitize(actual);
    if (expectedValue.isEmpty || actualValue.isEmpty) return false;
    return expectedValue == actualValue;
  }

  static Future<String> generate(String? deviceId, String userId) async {
    final normalizedDevice = sanitize(
      deviceId ?? await currentDeviceIdentifier(),
    );
    final normalizedUser = sanitize(userId);
    if (normalizedDevice.isEmpty) {
      return 'paired:$normalizedUser';
    }
    return 'paired:$normalizedUser:$normalizedDevice';
  }
}
