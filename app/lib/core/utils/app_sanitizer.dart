/// Input sanitization for all user-facing text before Firestore writes.
class AppSanitizer {
  AppSanitizer._();

  static final _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
  static final _multiSpace = RegExp(r'\s{2,}');

  /// General text: strip control chars, collapse whitespace, trim.
  static String text(String raw, {int maxLength = 1000}) {
    var s = raw.replaceAll(_controlChars, '');
    s = s.replaceAll(_multiSpace, ' ').trim();
    if (s.length > maxLength) s = s.substring(0, maxLength);
    return s;
  }

  /// Name fields: letters, spaces, hyphens, apostrophes, unicode letters.
  static String name(String raw, {int maxLength = 200}) {
    var s = text(raw, maxLength: maxLength);
    // Allow Unicode letters, spaces, hyphens, apostrophes, dots
    s = s.replaceAll(RegExp(r"[^\p{L}\p{M}\s\-'.]+", unicode: true), '');
    return s.trim();
  }

  /// SKU/code: alphanumeric + hyphens + underscores.
  static String sku(String raw, {int maxLength = 50}) {
    var s = text(raw, maxLength: maxLength);
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '');
    return s;
  }

  /// Phone: digits, +, -, spaces only.
  static String phone(String raw, {int maxLength = 20}) {
    var s = text(raw, maxLength: maxLength);
    s = s.replaceAll(RegExp(r'[^\d+\-\s]'), '');
    return s;
  }

  /// Amount strings: digits and single decimal point.
  static String amount(String raw) {
    var s = raw.replaceAll(RegExp(r'[^\d.]'), '');
    // Keep only first decimal point
    final firstDot = s.indexOf('.');
    if (firstDot >= 0) {
      s =
          s.substring(0, firstDot + 1) +
          s.substring(firstDot + 1).replaceAll('.', '');
    }
    return s;
  }

  /// Clamp a numeric value between [min] and [max].
  static double clamp(double value, {double min = 0, double max = 999999999}) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
