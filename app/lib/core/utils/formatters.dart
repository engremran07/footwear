import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppFormatters {
  AppFormatters._();

  static final _sar = NumberFormat.currency(symbol: 'SAR ', decimalDigits: 2);
  static final _num = NumberFormat('#,##0.##');
  static final _date = DateFormat('dd MMM yyyy');
  static final _dateTime = DateFormat('dd MMM yyyy, HH:mm');
  static final _period = DateFormat('MMM yyyy');

  static final _dateOnly = DateFormat('dd MMM yyyy');

  static String sar(double amount) => _sar.format(amount);
  static String currency(double amount, [String symbol = 'SAR']) =>
      _sar.format(amount);
  static String number(num value) => _num.format(value);

  static String date(Timestamp? ts) =>
      ts == null ? '—' : _date.format(ts.toDate());
  static String dateTime(Timestamp? ts) =>
      ts == null ? '—' : _dateTime.format(ts.toDate());
  static String dateOnly(DateTime dt) => _dateOnly.format(dt);
  static String period(String yyyyMm) {
    try {
      final parts = yyyyMm.split('-');
      final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]));
      return _period.format(dt);
    } catch (_) {
      return yyyyMm;
    }
  }

  static String currentPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String compact(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  /// Formats stock as:
  /// "X cartons Y pairs (X dozens Y pairs)"
  /// Example: "12 cartons 3 pairs (12 dozens 3 pairs)"
  static String stock(int pairs, int ppc) {
    if (ppc <= 0) return '$pairs pairs';
    final cartons = pairs ~/ ppc;
    final remaining = pairs % ppc;
    if (cartons == 0) return '$remaining pairs';
    if (remaining == 0) {
      return '$cartons cartons ($cartons dozens)';
    }
    return '$cartons cartons $remaining pairs ($cartons dozens $remaining pairs)';
  }

  static List<String> last12Periods() {
    final now = DateTime.now();
    return List.generate(12, (i) {
      final dt = DateTime(now.year, now.month - i);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    });
  }
}
