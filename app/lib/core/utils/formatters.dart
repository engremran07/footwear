import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical export file‐name types — use these with
/// [AppFormatters.exportFileName] instead of raw string literals.
abstract final class ExportNames {
  static const invoice = 'invoice';
  static const ledger = 'ledger';
  static const sellerReport = 'seller_report';
  static const inventoryReport = 'inventory_report';
  static const shopsAll = 'shops_all';
  static const shopsPerRoute = 'shops_per_route';
  static const shopsReport = 'shops_report';
  static const transactionsReport = 'transactions_report';
  static const outstandingReport = 'outstanding_report';
  static const badDebtsReport = 'bad_debts_report';
}

class AppFormatters {
  AppFormatters._();

  static final _sar = NumberFormat.currency(symbol: '﷼ ', decimalDigits: 2);
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

  /// Formats stock as dozens (primary) + optional extra pairs.
  ///
  /// quantity_available in Firestore stores PAIRS for legacy compat.
  /// The UI always shows and accepts DOZENS as primary (1 dozen = 12 pairs).
  /// ppc = pairs per dozen (always 12; kept as parameter for settings compat).
  ///
  /// Examples:
  ///   stock(0, 12)   → "0 dozens"
  ///   stock(12, 12)  → "1 dozen"
  ///   stock(15, 12)  → "1 dozen 3 pairs"
  ///   stock(24, 12)  → "2 dozens"
  ///   stock(5, 12)   → "0 dozens 5 pairs"
  static String stock(int pairs, int ppc) {
    if (ppc <= 0) return '$pairs pairs';
    final dozens = pairs ~/ ppc;
    final remaining = pairs % ppc;
    if (dozens == 0 && remaining == 0) return '0 dozens';
    if (dozens == 0) return '$remaining pairs';
    final dozenLabel = dozens == 1 ? '1 dozen' : '$dozens dozens';
    if (remaining == 0) return dozenLabel;
    return '$dozenLabel $remaining pairs';
  }

  /// Generates a standardized export filename base (no extension).
  /// Format: `{type}_{subject}_{YYYY-MM-DD}`
  /// [ExportSheet] appends `.pdf` / `.xlsx` / `.png` automatically.
  /// Callers using `Printing.sharePdf()` directly must append `.pdf`.
  static String exportFileName(String type, [String? subject]) {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final safeType = type.trim().toLowerCase().replaceAll(
      RegExp(r'[^\w]'),
      '_',
    );
    if (subject == null || subject.trim().isEmpty) return '${safeType}_$date';
    final safeSubj = subject
        .trim()
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '${safeType}_${safeSubj}_$date';
  }

  static List<String> last12Periods() {
    final now = DateTime.now();
    return List.generate(12, (i) {
      final dt = DateTime(now.year, now.month - i);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    });
  }
}
