import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppFormatters {
  AppFormatters._();

  static final _sar = NumberFormat.currency(symbol: 'SAR ', decimalDigits: 2);
  static final _pkr = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
  static final _num = NumberFormat('#,##0.##');
  static final _date = DateFormat('dd MMM yyyy');
  static final _dateTime = DateFormat('dd MMM yyyy, HH:mm');
  static final _period = DateFormat('MMM yyyy');

  static String sar(double amount) => _sar.format(amount);
  static String pkr(double amount) => _pkr.format(amount);
  static String currency(double amount, String symbol) =>
      symbol == 'PKR' ? pkr(amount) : sar(amount);
  static String number(num value) => _num.format(value);

  static String date(Timestamp? ts) =>
      ts == null ? '—' : _date.format(ts.toDate());
  static String dateTime(Timestamp? ts) =>
      ts == null ? '—' : _dateTime.format(ts.toDate());
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

  static List<String> last12Periods() {
    final now = DateTime.now();
    return List.generate(12, (i) {
      final dt = DateTime(now.year, now.month - i);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    });
  }
}
