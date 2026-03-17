// Bumps the app version in pubspec.yaml and syncs it to app_brand.dart.
//
// Usage:
//   dart run tool/bump_version.dart patch   # 1.0.0 → 1.0.1
//   dart run tool/bump_version.dart minor   # 1.0.0 → 1.1.0
//   dart run tool/bump_version.dart major   # 1.0.0 → 2.0.0
//   dart run tool/bump_version.dart build   # only increment +N
//   dart run tool/bump_version.dart         # (no arg) = build
import 'dart:io';

void main(List<String> args) {
  final mode = args.isEmpty ? 'build' : args.first.toLowerCase();
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found. Run from app/ directory.');
    exit(1);
  }

  final content = pubspecFile.readAsStringSync();
  final versionRegex =
      RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', multiLine: true);
  final match = versionRegex.firstMatch(content);
  if (match == null) {
    stderr.writeln('Error: No version line found in pubspec.yaml');
    exit(1);
  }

  var major = int.parse(match.group(1)!);
  var minor = int.parse(match.group(2)!);
  var patch = int.parse(match.group(3)!);
  var build = int.parse(match.group(4)!);

  final oldVersion = '$major.$minor.$patch+$build';

  switch (mode) {
    case 'major':
      major++;
      minor = 0;
      patch = 0;
      build++;
    case 'minor':
      minor++;
      patch = 0;
      build++;
    case 'patch':
      patch++;
      build++;
    case 'build':
      build++;
    default:
      stderr.writeln('Unknown mode: $mode. Use major|minor|patch|build');
      exit(1);
  }

  final newVersion = '$major.$minor.$patch+$build';

  // 1. Update pubspec.yaml
  final updatedPubspec = content.replaceFirst(
    'version: $oldVersion',
    'version: $newVersion',
  );
  pubspecFile.writeAsStringSync(updatedPubspec);

  // 2. Sync app_brand.dart
  _syncAppBrand('$major.$minor.$patch', build.toString());

  stdout.writeln('✓ Version bumped: $oldVersion → $newVersion ($mode)');
}

void _syncAppBrand(String version, String buildNumber) {
  final brandFile = File('lib/core/constants/app_brand.dart');
  if (!brandFile.existsSync()) {
    stderr.writeln('Warning: app_brand.dart not found, skipping sync.');
    return;
  }

  var content = brandFile.readAsStringSync();

  content = content.replaceFirstMapped(
    RegExp(r"static const String appVersion = '.*?';"),
    (_) => "static const String appVersion = '$version';",
  );
  content = content.replaceFirstMapped(
    RegExp(r"static const String buildNumber = '.*?';"),
    (_) => "static const String buildNumber = '$buildNumber';",
  );

  brandFile.writeAsStringSync(content);
}
