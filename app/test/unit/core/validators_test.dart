import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/core/utils/validators.dart';

void main() {
  group('AppValidators.required', () {
    test('returns validator function', () {
      final v = AppValidators.required();
      expect(v, isA<Function>());
    });

    test('rejects null input', () {
      expect(AppValidators.required()(null), isNotNull);
    });

    test('rejects empty string', () {
      expect(AppValidators.required()(''), isNotNull);
    });

    test('rejects whitespace-only string', () {
      expect(AppValidators.required()('   '), isNotNull);
    });

    test('accepts non-empty value', () {
      expect(AppValidators.required()('hello'), isNull);
    });

    test('includes field name in message when provided', () {
      final result = AppValidators.required('Password')(null);
      expect(result, contains('Password'));
    });

    test('uses generic message when no field name', () {
      final result = AppValidators.required()(null);
      expect(result, isNotNull);
      expect(result, isA<String>());
    });
  });

  group('AppValidators.positiveNumber', () {
    test('rejects null', () {
      expect(AppValidators.positiveNumber(null), isNotNull);
    });

    test('rejects empty string', () {
      expect(AppValidators.positiveNumber(''), isNotNull);
    });

    test('rejects non-numeric string', () {
      expect(AppValidators.positiveNumber('abc'), isNotNull);
    });

    test('rejects zero', () {
      expect(AppValidators.positiveNumber('0'), isNotNull);
    });

    test('rejects negative', () {
      expect(AppValidators.positiveNumber('-1'), isNotNull);
    });

    test('accepts positive integer', () {
      expect(AppValidators.positiveNumber('10'), isNull);
    });

    test('accepts positive decimal', () {
      expect(AppValidators.positiveNumber('3.14'), isNull);
    });
  });

  group('AppValidators.nonNegativeNumber', () {
    test('rejects null', () {
      expect(AppValidators.nonNegativeNumber(null), isNotNull);
    });

    test('rejects negative', () {
      expect(AppValidators.nonNegativeNumber('-0.01'), isNotNull);
    });

    test('accepts zero', () {
      expect(AppValidators.nonNegativeNumber('0'), isNull);
    });

    test('accepts positive', () {
      expect(AppValidators.nonNegativeNumber('99.5'), isNull);
    });
  });

  group('AppValidators.positiveInt', () {
    test('rejects null', () {
      expect(AppValidators.positiveInt(null), isNotNull);
    });

    test('rejects decimal', () {
      expect(AppValidators.positiveInt('3.5'), isNotNull);
    });

    test('rejects zero', () {
      expect(AppValidators.positiveInt('0'), isNotNull);
    });

    test('rejects negative', () {
      expect(AppValidators.positiveInt('-1'), isNotNull);
    });

    test('accepts positive integer', () {
      expect(AppValidators.positiveInt('5'), isNull);
    });
  });

  group('AppValidators.email', () {
    test('returns null for empty (optional field)', () {
      expect(AppValidators.email(''), isNull);
      expect(AppValidators.email(null), isNull);
    });

    test('rejects invalid email formats', () {
      expect(AppValidators.email('notanemail'), isNotNull);
      expect(AppValidators.email('missing@tld'), isNotNull);
      expect(AppValidators.email('@nodomain.com'), isNotNull);
    });

    test('accepts valid email', () {
      expect(AppValidators.email('user@example.com'), isNull);
      expect(AppValidators.email('user+tag@sub.domain.org'), isNull);
    });
  });

  group('AppValidators.phone', () {
    test('rejects null', () {
      expect(AppValidators.phone(null), isNotNull);
    });

    test('rejects empty', () {
      expect(AppValidators.phone(''), isNotNull);
    });

    test('rejects too-short number', () {
      expect(AppValidators.phone('123'), isNotNull);
    });

    test('accepts valid number', () {
      expect(AppValidators.phone('+966501234567'), isNull);
    });
  });

  group('AppValidators.sku', () {
    test('rejects empty', () {
      expect(AppValidators.sku(''), isNotNull);
    });

    test('rejects single character', () {
      expect(AppValidators.sku('A'), isNotNull);
    });

    test('accepts valid SKU', () {
      expect(AppValidators.sku('SKU-001'), isNull);
    });
  });

  group('AppValidators.minLength', () {
    test('rejects too-short value', () {
      expect(AppValidators.minLength(5)('abc'), equals('Minimum 5 characters'));
    });

    test('accepts value meeting min length', () {
      expect(AppValidators.minLength(3)('abc'), isNull);
    });

    test('returns error for null', () {
      expect(AppValidators.minLength(3)(null), equals('Minimum 3 characters'));
    });

    test('localizes and interpolates minimum length', () {
      expect(
        AppValidators.minLength(8, AppLocale.en)('short'),
        equals('Minimum 8 characters'),
      );
    });
  });

  group('AppValidators.maxLength', () {
    test('rejects too-long value with interpolated message', () {
      expect(
        AppValidators.maxLength(4)('12345'),
        equals('Maximum 4 characters'),
      );
    });

    test('accepts value within max length', () {
      expect(AppValidators.maxLength(5)('12345'), isNull);
    });

    test('returns null for null input', () {
      expect(AppValidators.maxLength(5)(null), isNull);
    });
  });

  group('Validators alias class', () {
    test('notEmpty rejects blank', () {
      expect(Validators.notEmpty(''), isNotNull);
      expect(Validators.notEmpty(null), isNotNull);
    });

    test('notEmpty accepts non-blank', () {
      expect(Validators.notEmpty('value'), isNull);
    });

    test('positiveInt delegates correctly', () {
      expect(Validators.positiveInt('0'), isNotNull);
      expect(Validators.positiveInt('1'), isNull);
    });

    test('positiveDouble delegates correctly', () {
      expect(Validators.positiveDouble('0'), isNotNull);
      expect(Validators.positiveDouble('1.5'), isNull);
    });

    test('nonNegativeDouble delegates correctly', () {
      expect(Validators.nonNegativeDouble('-1'), isNotNull);
      expect(Validators.nonNegativeDouble('0'), isNull);
    });
  });
}
