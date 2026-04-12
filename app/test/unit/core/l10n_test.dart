import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Extracts translation keys from a locale section in app_locale.dart.
/// Reads the section between [startMarker] and [endMarker] (exclusive).
List<String> _extractKeys(
  String source,
  String startMarker,
  String? endMarker,
) {
  final start = source.indexOf(startMarker);
  if (start == -1) return [];
  final end = endMarker != null
      ? source.indexOf(endMarker, start + startMarker.length)
      : source.length;
  final section = source.substring(start, end == -1 ? source.length : end);
  return RegExp(
    r"'([a-z][a-z0-9_]*)'\s*:",
  ).allMatches(section).map((m) => m.group(1)!).toList();
}

void main() {
  group('L10n parity — all locales must have identical key sets', () {
    late String source;
    late List<String> enKeys;
    late List<String> arKeys;
    late List<String> urKeys;

    setUpAll(() {
      // Run from app/ directory (flutter test runs from project root).
      final file = File('lib/core/l10n/app_locale.dart');
      source = file.readAsStringSync();

      enKeys = _extractKeys(source, 'AppLocale.en:', 'AppLocale.ar:');
      arKeys = _extractKeys(source, 'AppLocale.ar:', 'AppLocale.ur:');
      urKeys = _extractKeys(source, 'AppLocale.ur:', null);
    });

    test('EN locale has at least 372 keys (regression floor)', () {
      expect(
        enKeys.length,
        greaterThanOrEqualTo(372),
        reason: 'EN key count dropped below baseline. Keys added/removed?',
      );
    });

    test('AR key count equals EN key count', () {
      expect(
        arKeys.length,
        equals(enKeys.length),
        reason:
            'AR has ${arKeys.length} keys but EN has ${enKeys.length}. '
            'Run: grep the missing keys and add translations.',
      );
    });

    test('UR key count equals EN key count', () {
      expect(
        urKeys.length,
        equals(enKeys.length),
        reason:
            'UR has ${urKeys.length} keys but EN has ${enKeys.length}. '
            'Run: grep the missing keys and add translations.',
      );
    });

    test('AR contains every EN key', () {
      final arSet = arKeys.toSet();
      final missing = enKeys.where((k) => !arSet.contains(k)).toList();
      expect(missing, isEmpty, reason: 'AR missing keys: $missing');
    });

    test('UR contains every EN key', () {
      final urSet = urKeys.toSet();
      final missing = enKeys.where((k) => !urSet.contains(k)).toList();
      expect(missing, isEmpty, reason: 'UR missing keys: $missing');
    });

    test('login reset hint exists in all locales', () {
      expect(enKeys, contains('login_reset_email_hint'));
      expect(arKeys, contains('login_reset_email_hint'));
      expect(urKeys, contains('login_reset_email_hint'));
    });

    test('No duplicate keys in EN locale', () {
      final seen = <String>{};
      final dups = <String>[];
      for (final k in enKeys) {
        if (!seen.add(k)) dups.add(k);
      }
      expect(dups, isEmpty, reason: 'Duplicate EN keys: $dups');
    });

    test('No duplicate keys in AR locale', () {
      final seen = <String>{};
      final dups = <String>[];
      for (final k in arKeys) {
        if (!seen.add(k)) dups.add(k);
      }
      expect(dups, isEmpty, reason: 'Duplicate AR keys: $dups');
    });

    test('No duplicate keys in UR locale', () {
      final seen = <String>{};
      final dups = <String>[];
      for (final k in urKeys) {
        if (!seen.add(k)) dups.add(k);
      }
      expect(dups, isEmpty, reason: 'Duplicate UR keys: $dups');
    });
  });
}
