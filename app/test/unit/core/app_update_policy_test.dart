import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/constants/app_brand.dart';
import 'package:footwear_erp/core/utils/app_update_policy.dart';

void main() {
  group('AppUpdatePolicy', () {
    test('Android version code advances from the last Play upload by one', () {
      expect(AppBrand.androidVersionCode, 310191132);
    });

    test('requires an update below the configured minimum version', () {
      final decision = AppUpdatePolicy.evaluate(
        currentVersionCode: 310191131,
        minimumSupportedVersionCode: 310191132,
        updateAvailable: false,
        availableVersionCode: null,
        updatePriority: 0,
        flexibleUpdateAllowed: false,
        immediateUpdateAllowed: false,
      );

      expect(decision.isRequired, isTrue);
      expect(decision.canStartImmediateUpdate, isFalse);
      expect(decision.canStartFlexibleUpdate, isFalse);
    });

    test('does not require the configured minimum version itself', () {
      final decision = AppUpdatePolicy.evaluate(
        currentVersionCode: 310191132,
        minimumSupportedVersionCode: 310191132,
        updateAvailable: false,
        availableVersionCode: null,
        updatePriority: 0,
        flexibleUpdateAllowed: false,
        immediateUpdateAllowed: false,
      );

      expect(decision.isRequired, isFalse);
      expect(decision.hasOptionalUpdate, isFalse);
    });

    test('offers an available lower-priority release as a flexible update', () {
      final decision = AppUpdatePolicy.evaluate(
        currentVersionCode: 310191131,
        minimumSupportedVersionCode: 0,
        updateAvailable: true,
        availableVersionCode: 310191132,
        updatePriority: 3,
        flexibleUpdateAllowed: true,
        immediateUpdateAllowed: true,
      );

      expect(decision.isRequired, isFalse);
      expect(decision.hasOptionalUpdate, isTrue);
      expect(decision.canStartFlexibleUpdate, isTrue);
    });

    test(
      'requires an available release at the configured priority threshold',
      () {
        final decision = AppUpdatePolicy.evaluate(
          currentVersionCode: 310191131,
          minimumSupportedVersionCode: 0,
          updateAvailable: true,
          availableVersionCode: 310191132,
          updatePriority: 4,
          flexibleUpdateAllowed: true,
          immediateUpdateAllowed: true,
        );

        expect(decision.isRequired, isTrue);
        expect(decision.canStartImmediateUpdate, isTrue);
      },
    );

    test('never offers an update when Play reports no newer version', () {
      final decision = AppUpdatePolicy.evaluate(
        currentVersionCode: 310191132,
        minimumSupportedVersionCode: 0,
        updateAvailable: true,
        availableVersionCode: 310191131,
        updatePriority: 5,
        flexibleUpdateAllowed: true,
        immediateUpdateAllowed: true,
      );

      expect(decision.isRequired, isFalse);
      expect(decision.hasOptionalUpdate, isFalse);
    });

    test('ignores the version code when Play reports no update', () {
      final decision = AppUpdatePolicy.evaluate(
        currentVersionCode: 310191131,
        minimumSupportedVersionCode: 0,
        updateAvailable: false,
        availableVersionCode: 999999999,
        updatePriority: 5,
        flexibleUpdateAllowed: true,
        immediateUpdateAllowed: true,
      );

      expect(decision.isRequired, isFalse);
      expect(decision.hasOptionalUpdate, isFalse);
    });
  });
}
