import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/constants/app_brand.dart';

void main() {
  const packageName = 'footwear.com.pk';
  const legacyPackageName = 'footwear.pk.com';

  test('Android package identity is consistent across build configuration', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(
      RegExp(r'namespace\s*=\s*"([^"]+)"').firstMatch(gradle)?.group(1),
      packageName,
    );
    expect(
      RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle)?.group(1),
      packageName,
    );
    final codeBase = RegExp(
      r'val versionCode\s*=\s*([\d_]+)L\s*\+\s*buildNumber\.toLong\(\)',
    ).firstMatch(gradle)?.group(1);
    expect(
      int.parse(codeBase!.replaceAll('_', '')),
      AppBrand.androidVersionCodeBase,
    );
    expect(AppBrand.androidVersionCode, 310191132);

    final activity = File(
      'android/app/src/main/kotlin/footwear/com/pk/MainActivity.kt',
    );
    expect(activity.existsSync(), isTrue);
    expect(activity.readAsStringSync(), contains('package $packageName'));
    expect(
      File('android/app/src/main/kotlin/footwear/pk/com/MainActivity.kt')
          .existsSync(),
      isFalse,
    );

    final proguard = File('android/app/proguard-rules.pro').readAsStringSync();
    expect(proguard, contains('-keep class $packageName.**'));
    expect(proguard, isNot(contains(legacyPackageName)));

    final appfile = File('../fastlane/Appfile').readAsStringSync();
    final fastfile = File('../fastlane/Fastfile').readAsStringSync();
    expect(appfile, contains('package_name("$packageName")'));
    expect(fastfile, contains("package_name: '$packageName'"));
    expect(appfile, isNot(contains(legacyPackageName)));
    expect(fastfile, isNot(contains(legacyPackageName)));

    final googleServices = jsonDecode(
      File('android/app/google-services.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final clients = googleServices['client'] as List<dynamic>;
    final clientPackages = clients
        .map(
          (client) =>
              (client as Map<String, dynamic>)['client_info']
                  as Map<String, dynamic>,
        )
        .map(
          (clientInfo) =>
              (clientInfo['android_client_info']
                  as Map<String, dynamic>)['package_name'],
        )
        .cast<String>()
        .toList();
    expect(clientPackages, [packageName]);

    final androidOptions = File('lib/firebase_options.dart').readAsStringSync();
    final androidOptionsBlock = RegExp(
      r'static const FirebaseOptions android = FirebaseOptions\((.*?)\n\s*\);',
      dotAll: true,
    ).firstMatch(androidOptions)?.group(1);
    final firebaseAppId = androidOptionsBlock == null
        ? null
        : RegExp(r"appId:\s*'([^']+)'")
              .firstMatch(androidOptionsBlock)
              ?.group(1);
    final googleServicesAppId =
        ((clients.single as Map<String, dynamic>)['client_info']
                as Map<String, dynamic>)['mobilesdk_app_id']
            as String;
    expect(firebaseAppId, googleServicesAppId);
  });
}
