import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/app_sanitizer.dart';

void main() {
  group('AppSanitizer.text', () {
    test('trims leading/trailing whitespace', () {
      expect(AppSanitizer.text('  hello  '), equals('hello'));
    });

    test('collapses multiple spaces', () {
      expect(AppSanitizer.text('a  b   c'), equals('a b c'));
    });

    test('strips control characters', () {
      expect(AppSanitizer.text('ab\x01\x07cd'), equals('abcd'));
    });

    test('truncates to maxLength', () {
      final result = AppSanitizer.text('abcdefgh', maxLength: 4);
      expect(result, equals('abcd'));
    });

    test('empty string returns empty', () {
      expect(AppSanitizer.text(''), equals(''));
    });
  });

  group('AppSanitizer.name', () {
    test('removes non-letter characters like digits and symbols', () {
      // digits stripped; letters kept
      final result = AppSanitizer.name('Ali123!');
      expect(result, isNot(contains('1')));
      expect(result, isNot(contains('!')));
      expect(result, contains('Ali'));
    });

    test('preserves hyphens and apostrophes', () {
      final result = AppSanitizer.name("O'Brien-Smith");
      expect(result, equals("O'Brien-Smith"));
    });

    test('preserves unicode letters', () {
      expect(AppSanitizer.name('محمد'), equals('محمد'));
    });

    test('truncates to maxLength', () {
      final result = AppSanitizer.name('AbCdEf', maxLength: 3);
      expect(result.length, lessThanOrEqualTo(3));
    });
  });

  group('AppSanitizer.sku', () {
    test('keeps alphanumeric, hyphens, underscores', () {
      expect(AppSanitizer.sku('SKU-001_A'), equals('SKU-001_A'));
    });

    test('strips spaces and special chars', () {
      expect(AppSanitizer.sku('SKU 001!@#'), equals('SKU001'));
    });

    test('truncates to maxLength', () {
      final result = AppSanitizer.sku('ABCDEFGHIJ', maxLength: 5);
      expect(result, equals('ABCDE'));
    });
  });

  group('AppSanitizer.phone', () {
    test('keeps digits, plus, hyphens, spaces', () {
      expect(AppSanitizer.phone('+92-300 1234567'), equals('+92-300 1234567'));
    });

    test('strips non-phone characters', () {
      expect(AppSanitizer.phone('(+92) 300-abc'), equals('+92 300-'));
    });
  });

  group('AppSanitizer.amount', () {
    test('keeps digits and single decimal', () {
      expect(AppSanitizer.amount('1234.56'), equals('1234.56'));
    });

    test('strips non-digit non-dot characters', () {
      // 'Rs.1,200.50' → strip non-digit/dot → '.1200.50' → keep first dot → '.120050'
      expect(AppSanitizer.amount('Rs.1,200.50'), equals('.120050'));
    });

    test('keeps only first decimal point', () {
      expect(AppSanitizer.amount('1.2.3'), equals('1.23'));
    });

    test('integer string passes through', () {
      expect(AppSanitizer.amount('999'), equals('999'));
    });
  });

  group('AppSanitizer.clamp', () {
    test('returns value when within range', () {
      expect(AppSanitizer.clamp(500, min: 0, max: 1000), equals(500));
    });

    test('clamps below min', () {
      expect(AppSanitizer.clamp(-10, min: 0, max: 1000), equals(0));
    });

    test('clamps above max', () {
      expect(AppSanitizer.clamp(2000, min: 0, max: 1000), equals(1000));
    });

    test('exactly at min boundary returns min', () {
      expect(AppSanitizer.clamp(0, min: 0, max: 100), equals(0));
    });

    test('exactly at max boundary returns max', () {
      expect(AppSanitizer.clamp(100, min: 0, max: 100), equals(100));
    });
  });
}
