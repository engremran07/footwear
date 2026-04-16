import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footwear_erp/providers/changelog_provider.dart';

void main() {
  group('changelogSeenVersionProvider', () {
    setUp(() {
      // Reset SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
    });

    test('returns null when no version has been seen', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container.read(
        changelogSeenVersionProvider.future,
      );
      expect(result, isNull);
    });

    test('returns version after markChangelogSeen is called', () async {
      await markChangelogSeen('3.7.6');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container.read(
        changelogSeenVersionProvider.future,
      );
      expect(result, equals('3.7.6'));
    });

    test('overwrites previous version when called again', () async {
      await markChangelogSeen('3.7.5');
      await markChangelogSeen('3.7.6');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container.read(
        changelogSeenVersionProvider.future,
      );
      expect(result, equals('3.7.6'), reason: 'latest version should win');
    });

    test('version does not match a different release', () async {
      await markChangelogSeen('3.7.5');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final seen = await container.read(changelogSeenVersionProvider.future);
      expect(seen, isNot(equals('3.7.6')));
    });
  });

  group('markChangelogSeen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists version to SharedPreferences', () async {
      await markChangelogSeen('3.7.6');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('whats_new_seen_version'), equals('3.7.6'));
    });

    test('handles empty version string without throwing', () async {
      // Should not throw even with an empty version
      expect(() async => markChangelogSeen(''), returnsNormally);
    });
  });
}
