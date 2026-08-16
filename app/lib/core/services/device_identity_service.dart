import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

class DeviceIdentityService {
  DeviceIdentityService._();

  static final DeviceIdentityService instance = DeviceIdentityService._();

  Future<String> currentDeviceId() async {
    if (kIsWeb) {
      return 'web:${DateTime.now().microsecondsSinceEpoch}';
    }

    final os = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    final host = Platform.localHostname;
    final base = '$os:$version:$host';
    return 'device:${base.replaceAll(RegExp(r'\s+'), '').toLowerCase()}';
  }
}
