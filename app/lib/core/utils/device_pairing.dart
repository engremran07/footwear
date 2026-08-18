import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

class DevicePairing {
  const DevicePairing._();

  static String sanitize(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  static String currentDeviceIdentifier() {
    if (kIsWeb) {
      // P2-15 FIX: Web device ID time-based issue
      // TODO: Replace with stable UUID persisted to browser storage,
      // or omit device pairing on web entirely.
      // For now, return empty string to disable device pairing on web.
      return '';
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

  static String generate(String? deviceId, String userId) {
    final normalizedDevice = sanitize(deviceId ?? currentDeviceIdentifier());
    final normalizedUser = sanitize(userId);
    if (normalizedDevice.isEmpty) {
      return 'paired:$normalizedUser';
    }
    return 'paired:$normalizedUser:$normalizedDevice';
  }
}
