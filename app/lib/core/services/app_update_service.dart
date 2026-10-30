import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_brand.dart';

const String minimumSupportedVersionCodeKey = 'minimum_supported_version_code';

enum AppUpdateInstallStatus { downloaded, other }

enum AppUpdateActionResult { success, userCancelled, failed }

class AppUpdateSnapshot {
  const AppUpdateSnapshot({
    required this.updateAvailable,
    required this.availableVersionCode,
    required this.updatePriority,
    required this.flexibleUpdateAllowed,
    required this.immediateUpdateAllowed,
    required this.immediateUpdateInProgress,
    required this.flexibleUpdateDownloaded,
  });

  final bool updateAvailable;
  final int? availableVersionCode;
  final int updatePriority;
  final bool flexibleUpdateAllowed;
  final bool immediateUpdateAllowed;
  final bool immediateUpdateInProgress;
  final bool flexibleUpdateDownloaded;
}

abstract interface class AppUpdateGateway {
  bool get isSupported;
  Stream<AppUpdateInstallStatus> get installUpdateListener;

  Future<int> fetchMinimumSupportedVersionCode();
  Future<AppUpdateSnapshot> checkForUpdate();
  Future<AppUpdateActionResult> performImmediateUpdate();
  Future<AppUpdateActionResult> startFlexibleUpdate();
  Future<void> completeFlexibleUpdate();
  Future<bool> openStoreListing();
}

final appUpdateGatewayProvider = Provider<AppUpdateGateway>(
  (ref) => PlayAppUpdateGateway(),
);

class PlayAppUpdateGateway implements AppUpdateGateway {
  static const _remoteConfigTimeout = Duration(seconds: 3);

  @override
  bool get isSupported =>
      !kIsWeb && !kDebugMode && defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<AppUpdateInstallStatus> get installUpdateListener =>
      InAppUpdate.installUpdateListener.map(
        (status) => status == InstallStatus.downloaded
            ? AppUpdateInstallStatus.downloaded
            : AppUpdateInstallStatus.other,
      );

  @override
  Future<int> fetchMinimumSupportedVersionCode() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.ensureInitialized().timeout(_remoteConfigTimeout);
      await remoteConfig.setDefaults({minimumSupportedVersionCodeKey: 0});
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: _remoteConfigTimeout,
          minimumFetchInterval: const Duration(hours: 12),
        ),
      );
      try {
        await remoteConfig.fetchAndActivate().timeout(_remoteConfigTimeout);
      } on FirebaseException catch (error, stackTrace) {
        recordAppUpdateError(
          error,
          stackTrace,
          'Remote Config fetch failed; retaining cached update policy.',
        );
      } on TimeoutException catch (error, stackTrace) {
        recordAppUpdateError(
          error,
          stackTrace,
          'Remote Config fetch timed out; retaining cached update policy.',
        );
      }

      final minimumVersionCode = remoteConfig.getInt(
        minimumSupportedVersionCodeKey,
      );
      return minimumVersionCode > 0 ? minimumVersionCode : 0;
    } on FirebaseException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Remote Config initialization failed; update gate is using its default.',
      );
      return 0;
    } on TimeoutException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Remote Config initialization timed out; update gate is using its default.',
      );
      return 0;
    } on PlatformException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Remote Config platform call failed; update gate is using its default.',
      );
      return 0;
    } on MissingPluginException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Remote Config plugin is unavailable; update gate is using its default.',
      );
      return 0;
    }
  }

  @override
  Future<AppUpdateSnapshot> checkForUpdate() async {
    final info = await InAppUpdate.checkForUpdate();
    return AppUpdateSnapshot(
      updateAvailable:
          info.updateAvailability == UpdateAvailability.updateAvailable,
      availableVersionCode: info.availableVersionCode,
      updatePriority: info.updatePriority,
      flexibleUpdateAllowed: info.flexibleUpdateAllowed,
      immediateUpdateAllowed: info.immediateUpdateAllowed,
      immediateUpdateInProgress:
          info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress,
      flexibleUpdateDownloaded: info.installStatus == InstallStatus.downloaded,
    );
  }

  @override
  Future<AppUpdateActionResult> performImmediateUpdate() async {
    return _mapResult(await InAppUpdate.performImmediateUpdate());
  }

  @override
  Future<AppUpdateActionResult> startFlexibleUpdate() async {
    return _mapResult(await InAppUpdate.startFlexibleUpdate());
  }

  AppUpdateActionResult _mapResult(AppUpdateResult result) => switch (result) {
    AppUpdateResult.success => AppUpdateActionResult.success,
    AppUpdateResult.userDeniedUpdate => AppUpdateActionResult.userCancelled,
    AppUpdateResult.inAppUpdateFailed => AppUpdateActionResult.failed,
  };

  @override
  Future<void> completeFlexibleUpdate() => InAppUpdate.completeFlexibleUpdate();

  @override
  Future<bool> openStoreListing() async {
    final storeUri = Uri(
      scheme: 'market',
      host: 'details',
      queryParameters: {'id': AppBrand.androidPackageName},
    );
    if (await launchUrl(storeUri, mode: LaunchMode.externalApplication)) {
      return true;
    }

    final webUri = Uri.https('play.google.com', '/store/apps/details', {
      'id': AppBrand.androidPackageName,
    });
    return launchUrl(webUri, mode: LaunchMode.externalApplication);
  }
}

void recordAppUpdateError(Object error, StackTrace stackTrace, String reason) {
  if (kIsWeb || Firebase.apps.isEmpty) return;
  unawaited(
    FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: reason),
  );
}
