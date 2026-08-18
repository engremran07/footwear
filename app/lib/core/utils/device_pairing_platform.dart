import 'dart:io' show Platform;

class DevicePairingRuntime {
  const DevicePairingRuntime._();

  static String currentDeviceIdentifier() {
    final os = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    final host = Platform.localHostname;
    final base = '$os:$version:$host';
    return base;
  }
}
