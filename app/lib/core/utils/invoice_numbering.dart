abstract final class InvoiceNumbering {
  static int nextSequence(Map<String, dynamic>? settingsData) {
    int counterValue(String key) {
      if (settingsData == null || !settingsData.containsKey(key)) return 0;
      final value = settingsData[key];
      if (value is! num || !value.isFinite || value < 0 || value % 1 != 0) {
        throw StateError('Invalid invoice sequence counter: $key');
      }
      return value.toInt();
    }

    final invoiceSequence = counterValue('last_invoice_number');
    final receiptSequence = counterValue('last_cash_receipt_number');
    final highestSequence = invoiceSequence > receiptSequence
        ? invoiceSequence
        : receiptSequence;
    return highestSequence + 1;
  }

  static String sale(int sequence) => _format('INV', sequence);

  static String creditNote(int sequence) => _format('CN', sequence);

  static String receipt(int sequence) => _format('REC', sequence);

  static String _format(String prefix, int sequence) {
    if (sequence <= 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Must be positive');
    }
    return '$prefix-${sequence.toString().padLeft(4, '0')}';
  }
}
