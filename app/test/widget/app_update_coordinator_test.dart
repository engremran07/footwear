import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/constants/app_brand.dart';
import 'package:footwear_erp/core/services/app_update_service.dart';
import 'package:footwear_erp/core/utils/app_update_policy.dart';
import 'package:footwear_erp/widgets/app_update_coordinator.dart';

void main() {
  testWidgets('optional updates use the flexible Play flow when available', (
    tester,
  ) async {
    final gateway = _FakeAppUpdateGateway(
      minimumVersionCode: 0,
      snapshot: AppUpdateSnapshot(
        updateAvailable: true,
        availableVersionCode: AppBrand.androidVersionCode + 1,
        updatePriority: 0,
        flexibleUpdateAllowed: true,
        immediateUpdateAllowed: true,
        immediateUpdateInProgress: false,
        flexibleUpdateDownloaded: false,
      ),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();

    expect(gateway.flexibleUpdateCalls, 1);
    expect(find.text('Ready app'), findsOneWidget);
  });

  testWidgets('required minimum version gates app and offers store fallback', (
    tester,
  ) async {
    final gateway = _FakeAppUpdateGateway(
      minimumVersionCode: AppBrand.androidVersionCode + 1,
      checkError: PlatformException(code: 'play-unavailable'),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Ready app'), findsNothing);
    await tester.tap(find.text('Open Google Play'));
    await tester.pumpAndSettle();

    expect(gateway.storeListingCalls, 1);
  });

  testWidgets('priority-required update starts immediate flow', (tester) async {
    final gateway = _FakeAppUpdateGateway(
      minimumVersionCode: 0,
      snapshot: AppUpdateSnapshot(
        updateAvailable: true,
        availableVersionCode: AppBrand.androidVersionCode + 1,
        updatePriority: AppUpdatePolicy.requiredUpdatePriority,
        flexibleUpdateAllowed: true,
        immediateUpdateAllowed: true,
        immediateUpdateInProgress: false,
        flexibleUpdateDownloaded: false,
      ),
      immediateResult: AppUpdateActionResult.userCancelled,
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(gateway.immediateUpdateCalls, 1);
    expect(find.text('Update required'), findsOneWidget);
    expect(find.textContaining('required to continue'), findsOneWidget);
  });

  testWidgets('unavailable Play update check fails open without a minimum', (
    tester,
  ) async {
    final gateway = _FakeAppUpdateGateway(
      minimumVersionCode: 0,
      checkError: PlatformException(code: 'play-unavailable'),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.text('Ready app'), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
  });
}

Widget _app(_FakeAppUpdateGateway gateway) {
  return ProviderScope(
    overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
    child: const MaterialApp(
      home: AppUpdateCoordinator(child: Text('Ready app')),
    ),
  );
}

class _FakeAppUpdateGateway implements AppUpdateGateway {
  _FakeAppUpdateGateway({
    required this.minimumVersionCode,
    this.snapshot,
    this.checkError,
    this.immediateResult = AppUpdateActionResult.success,
  });

  final int minimumVersionCode;
  final AppUpdateSnapshot? snapshot;
  final Object? checkError;
  final AppUpdateActionResult immediateResult;
  int immediateUpdateCalls = 0;
  int flexibleUpdateCalls = 0;
  int storeListingCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Stream<AppUpdateInstallStatus> get installUpdateListener =>
      const Stream<AppUpdateInstallStatus>.empty();

  @override
  Future<int> fetchMinimumSupportedVersionCode() async => minimumVersionCode;

  @override
  Future<AppUpdateSnapshot> checkForUpdate() async {
    if (checkError != null) {
      Error.throwWithStackTrace(checkError!, StackTrace.current);
    }
    return snapshot!;
  }

  @override
  Future<AppUpdateActionResult> performImmediateUpdate() async {
    immediateUpdateCalls++;
    return immediateResult;
  }

  @override
  Future<AppUpdateActionResult> startFlexibleUpdate() async {
    flexibleUpdateCalls++;
    return AppUpdateActionResult.success;
  }

  @override
  Future<void> completeFlexibleUpdate() async {}

  @override
  Future<bool> openStoreListing() async {
    storeListingCalls++;
    return true;
  }
}
