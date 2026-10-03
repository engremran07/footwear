import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_brand.dart';

class DeviceInstallationMetadata {
  final String installationId;
  final String brand;
  final String model;
  final String platform;
  final String osVersion;
  final String appVersion;

  const DeviceInstallationMetadata({
    required this.installationId,
    required this.brand,
    required this.model,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
  });

  String get displayName =>
      [brand, model].where((value) => value.trim().isNotEmpty).join(' ');
}

class DeviceInstallation {
  DeviceInstallation._();

  static const _installationIdKey = 'access.device.installation_id';
  static Future<String>? _installationIdFuture;

  static Future<DeviceInstallationMetadata> current() async {
    final installationId = await (_installationIdFuture ??= _loadId());
    final deviceInfo = DeviceInfoPlugin();
    var brand = '';
    var model = '';
    var osVersion = '';
    var platform = 'unknown';

    if (kIsWeb) {
      final info = await deviceInfo.webBrowserInfo;
      brand = info.browserName.name;
      osVersion = info.appVersion ?? '';
      platform = 'web';
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await deviceInfo.androidInfo;
          brand = info.brand;
          model = info.model;
          osVersion = info.version.release;
          platform = 'android';
        case TargetPlatform.iOS:
          final info = await deviceInfo.iosInfo;
          brand = 'Apple';
          model = info.utsname.machine;
          osVersion = info.systemVersion;
          platform = 'ios';
        case TargetPlatform.macOS:
          final info = await deviceInfo.macOsInfo;
          brand = 'Apple';
          model = info.model;
          osVersion = info.osRelease;
          platform = 'macos';
        case TargetPlatform.windows:
          final info = await deviceInfo.windowsInfo;
          brand = 'Microsoft';
          model = info.productName;
          osVersion = info.displayVersion;
          platform = 'windows';
        case TargetPlatform.linux:
          final info = await deviceInfo.linuxInfo;
          brand = info.name;
          model = info.prettyName;
          osVersion = info.version ?? '';
          platform = 'linux';
        case TargetPlatform.fuchsia:
          platform = 'fuchsia';
      }
    }

    return DeviceInstallationMetadata(
      installationId: installationId,
      brand: brand.trim(),
      model: model.trim(),
      platform: platform,
      osVersion: osVersion.trim(),
      appVersion: AppBrand.versionDisplay,
    );
  }

  static Future<String> _loadId() async {
    final preferences = await SharedPreferences.getInstance();
    final storedId = preferences.getString(_installationIdKey)?.trim();
    if (storedId != null && storedId.isNotEmpty) return storedId;
    final installationId = const Uuid().v4();
    await preferences.setString(_installationIdKey, installationId);
    return installationId;
  }
}
