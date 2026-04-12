import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/formatters.dart';

void main() {
  // Fixed timestamp: 2024-01-15 10:30:00 UTC
  final ts2024Jan15 = Timestamp.fromDate(DateTime.utc(2024, 1, 15, 10, 30, 0));

  group('AppFormatters.sar', () {
    test('formats zero', () {
      expect(AppFormatters.sar(0), contains('﷼'));
    });

    test('formats positive amount with 2 decimal places', () {
      final result = AppFormatters.sar(1234.5);
      expect(result, contains('﷼'));
      expect(result, contains('1,234.50'));
    });

    test('formats 1234.56 with comma separator', () {
      // TEST-027
      final result = AppFormatters.sar(1234.56);
      expect(result, contains('﷼'));
      expect(result, contains('1,234.56'));
    });

    test('formats negative amount keeping rial symbol', () {
      // TEST-028
      final result = AppFormatters.sar(-500.0);
      expect(result, contains('﷼'));
      expect(result, contains('500.00'));
    });

    test('formats zero as 0.00', () {
      // TEST-029
      final result = AppFormatters.sar(0.0);
      expect(result, contains('﷼'));
      expect(result, contains('0.00'));
    });

    test('formats large amount with full precision not compact', () {
      // TEST-030
      final result = AppFormatters.sar(1000000.0);
      expect(result, contains('﷼'));
      expect(result, contains('1,000,000.00'));
      expect(result, isNot(contains('M')));
    });
  });

  group('AppFormatters.currency', () {
    test('uses sar for SAR symbol', () {
      expect(AppFormatters.currency(1000.0, 'SAR'), contains('﷼'));
    });

    test('uses sar for any symbol', () {
      // All currencies now format as ﷼
      expect(AppFormatters.currency(1000.0, 'USD'), contains('﷼'));
    });
  });

  group('AppFormatters.number', () {
    test('formats with thousands separator', () {
      expect(AppFormatters.number(1000000), contains('1,000,000'));
    });

    test('formats small number', () {
      expect(AppFormatters.number(42), '42');
    });

    test('strips trailing zeros on decimals', () {
      final result = AppFormatters.number(1.5);
      expect(result, '1.5');
    });
  });

  group('AppFormatters.date', () {
    test('returns dash for null timestamp', () {
      expect(AppFormatters.date(null), '—');
    });

    test('formats timestamp as dd MMM yyyy', () {
      final result = AppFormatters.date(ts2024Jan15);
      expect(result, '15 Jan 2024');
    });
  });

  group('AppFormatters.dateTime', () {
    test('returns dash for null', () {
      expect(AppFormatters.dateTime(null), '—');
    });

    test('formats with time component', () {
      final result = AppFormatters.dateTime(ts2024Jan15);
      expect(result, contains('15 Jan 2024'));
      expect(result, contains(':'));
    });
  });

  group('AppFormatters.period', () {
    test('formats YYYY-MM to Mon YYYY', () {
      final result = AppFormatters.period('2024-01');
      expect(result, 'Jan 2024');
    });

    test('formats December', () {
      expect(AppFormatters.period('2023-12'), 'Dec 2023');
    });

    test('returns input on malformed string', () {
      expect(AppFormatters.period('invalid'), 'invalid');
    });
  });

  group('AppFormatters.currentPeriod', () {
    test('returns YYYY-MM format', () {
      final result = AppFormatters.currentPeriod();
      expect(RegExp(r'^\d{4}-\d{2}$').hasMatch(result), isTrue);
    });

    test('matches current year and month', () {
      final now = DateTime.now();
      final expected = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      expect(AppFormatters.currentPeriod(), expected);
    });
  });

  group('AppFormatters.compact', () {
    test('formats millions', () {
      expect(AppFormatters.compact(1500000), '1.5M');
    });

    test('formats thousands', () {
      expect(AppFormatters.compact(3500), '3.5K');
    });

    test('formats small numbers as integer string', () {
      expect(AppFormatters.compact(999), '999');
    });

    test('formats zero', () {
      expect(AppFormatters.compact(0), '0');
    });
  });

  group('AppFormatters.last12Periods', () {
    test('returns exactly 12 periods', () {
      expect(AppFormatters.last12Periods(), hasLength(12));
    });

    test('first period is current month', () {
      final result = AppFormatters.last12Periods();
      expect(result.first, AppFormatters.currentPeriod());
    });

    test('all periods have YYYY-MM format', () {
      for (final p in AppFormatters.last12Periods()) {
        expect(
          RegExp(r'^\d{4}-\d{2}$').hasMatch(p),
          isTrue,
          reason: '$p does not match YYYY-MM',
        );
      }
    });
  });
}
