import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/data/changelog_data.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';

void main() {
  group('kChangelog', () {
    test('list is non-empty', () {
      expect(kChangelog, isNotEmpty);
    });

    test('first entry is the current release', () {
      final first = kChangelog.first;
      expect(first.version, isNotEmpty);
      expect(first.date, isNotEmpty);
      expect(first.items, isNotEmpty);
    });

    test('every entry has a non-empty version, date, and items', () {
      for (final entry in kChangelog) {
        expect(entry.version, isNotEmpty, reason: 'version must not be empty');
        expect(entry.date, isNotEmpty, reason: 'date must not be empty');
        expect(
          entry.items,
          isNotEmpty,
          reason: 'items list must not be empty for version ${entry.version}',
        );
      }
    });

    test('every item has an emoji and trilingual text', () {
      for (final entry in kChangelog) {
        for (final item in entry.items) {
          expect(
            item.emoji,
            isNotEmpty,
            reason: 'emoji must not be empty in v${entry.version}',
          );
          expect(
            item.textFor(AppLocale.en),
            isNotEmpty,
            reason: 'EN text must not be empty in v${entry.version}',
          );
          expect(
            item.textFor(AppLocale.ar),
            isNotEmpty,
            reason: 'AR text must not be empty in v${entry.version}',
          );
          expect(
            item.textFor(AppLocale.ur),
            isNotEmpty,
            reason: 'UR text must not be empty in v${entry.version}',
          );
        }
      }
    });
  });

  group('ChangelogItem.textFor', () {
    const item = ChangelogItem(
      emoji: '🛠️',
      text: {
        AppLocale.en: 'English text',
        AppLocale.ar: 'النص العربي',
        AppLocale.ur: 'اردو متن',
      },
    );

    test('returns correct EN text', () {
      expect(item.textFor(AppLocale.en), equals('English text'));
    });

    test('returns correct AR text', () {
      expect(item.textFor(AppLocale.ar), equals('النص العربي'));
    });

    test('returns correct UR text', () {
      expect(item.textFor(AppLocale.ur), equals('اردو متن'));
    });

    test('falls back to EN when locale missing', () {
      const partialItem = ChangelogItem(
        emoji: '📌',
        text: {AppLocale.en: 'Fallback text'},
      );
      // AR and UR are missing → should fall back to EN
      expect(partialItem.textFor(AppLocale.ar), equals('Fallback text'));
      expect(partialItem.textFor(AppLocale.ur), equals('Fallback text'));
    });

    test('returns empty string when no locales available', () {
      const emptyItem = ChangelogItem(emoji: '❓', text: {});
      expect(emptyItem.textFor(AppLocale.en), equals(''));
    });
  });

  group('ChangelogEntry', () {
    test('version 3.7.6 is present and has PDF fix entry', () {
      final v376 = kChangelog.where((e) => e.version == '3.7.6').toList();
      expect(v376, hasLength(1), reason: 'exactly one v3.7.6 entry expected');
      final items = v376.first.items;
      final hasPdfFix = items.any(
        (i) =>
            i.textFor(AppLocale.en).toLowerCase().contains('pdf') ||
            i.textFor(AppLocale.en).toLowerCase().contains('something went'),
      );
      expect(hasPdfFix, isTrue, reason: 'v3.7.6 must describe the PDF fix');
    });
  });
}
