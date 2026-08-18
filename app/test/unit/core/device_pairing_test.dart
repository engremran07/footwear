import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/device_pairing.dart';

void main() {
  group('DevicePairing', () {
    test('sanitize normalizes device IDs consistently', () {
      expect(
        DevicePairing.sanitize(' Android-ABC:123 '),
        equals('android-abc:123'),
      );
    });

    test('matches accepts equivalent device IDs regardless of casing', () {
      expect(DevicePairing.matches('android:abc123', 'ANDROID:ABC123'), isTrue);
    });

    test('matches rejects mismatched identifiers', () {
      expect(
        DevicePairing.matches('android:abc123', 'android:def456'),
        isFalse,
      );
    });
  });
}
