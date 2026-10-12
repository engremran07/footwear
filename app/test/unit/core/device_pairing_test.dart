import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/services/device_installation.dart';

void main() {
  group('DeviceInstallationMetadata', () {
    test('displayName combines non-empty brand and model', () {
      const metadata = DeviceInstallationMetadata(
        installationId: 'installation-123',
        brand: 'Samsung',
        model: 'Galaxy A14',
        platform: 'android',
        osVersion: '16',
        appVersion: 'test',
      );
      expect(metadata.displayName, 'Samsung Galaxy A14');
    });

    test('displayName tolerates missing device labels', () {
      const metadata = DeviceInstallationMetadata(
        installationId: 'installation-123',
        brand: ' ',
        model: 'Browser',
        platform: 'web',
        osVersion: '',
        appVersion: 'test',
      );
      expect(metadata.displayName, 'Browser');
    });
  });
}
