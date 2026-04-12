import '../l10n/app_locale.dart';

class AppValidators {
  AppValidators._();

  /// Returns a validator function that rejects blank values.
  /// Pass an optional [fieldName] to include it in the error message.
  /// Pass [locale] to get translated messages.
  static String? Function(String?) required([
    String? fieldName,
    AppLocale? locale,
  ]) {
    return (String? value) {
      if (value == null || value.trim().isEmpty) {
        if (fieldName != null) {
          return '$fieldName ${trRead('required', locale ?? AppLocale.en).toLowerCase()}';
        }
        return trRead('required_field', locale ?? AppLocale.en);
      }
      return null;
    };
  }

  static String? positiveNumber(String? value, [AppLocale? locale]) {
    final l = locale ?? AppLocale.en;
    if (value == null || value.trim().isEmpty) return trRead('required', l);
    final n = double.tryParse(value.trim());
    if (n == null) return trRead('must_be_number', l);
    if (n <= 0) return trRead('must_be_greater_zero', l);
    return null;
  }

  static String? nonNegativeNumber(String? value, [AppLocale? locale]) {
    final l = locale ?? AppLocale.en;
    if (value == null || value.trim().isEmpty) return trRead('required', l);
    final n = double.tryParse(value.trim());
    if (n == null) return trRead('must_be_number', l);
    if (n < 0) return trRead('cannot_be_negative', l);
    return null;
  }

  static String? positiveInt(String? value, [AppLocale? locale]) {
    final l = locale ?? AppLocale.en;
    if (value == null || value.trim().isEmpty) return trRead('required', l);
    final n = int.tryParse(value.trim());
    if (n == null) return trRead('must_be_whole_number', l);
    if (n <= 0) return trRead('must_be_greater_zero', l);
    return null;
  }

  static String? email(String? value, [AppLocale? locale]) {
    if (value == null || value.trim().isEmpty) return null; // optional
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!re.hasMatch(value.trim())) {
      return trRead('invalid_email', locale ?? AppLocale.en);
    }
    return null;
  }

  static String? phone(String? value, [AppLocale? locale]) {
    final l = locale ?? AppLocale.en;
    if (value == null || value.trim().isEmpty) {
      return trRead('phone_required', l);
    }
    if (value.trim().length < 7) return trRead('phone_too_short', l);
    return null;
  }

  static String? sku(String? value, [AppLocale? locale]) {
    final l = locale ?? AppLocale.en;
    if (value == null || value.trim().isEmpty) return trRead('sku_required', l);
    if (value.trim().length < 2) return trRead('sku_too_short', l);
    return null;
  }

  static String? Function(String?) minLength(int min, [AppLocale? locale]) =>
      (String? value) {
        if (value == null || value.trim().length < min) {
          return trRead(
            'min_n_chars',
            locale ?? AppLocale.en,
          ).replaceAll('%d', '$min');
        }
        return null;
      };

  static String? Function(String?) maxLength(int max, [AppLocale? locale]) =>
      (String? value) {
        if (value != null && value.trim().length > max) {
          return trRead(
            'max_n_chars',
            locale ?? AppLocale.en,
          ).replaceAll('%d', '$max');
        }
        return null;
      };
}

/// Convenience alias so screens can use `Validators.notEmpty` etc.
class Validators {
  Validators._();

  static String? notEmpty(String? value, [AppLocale? locale]) =>
      AppValidators.required(null, locale)(value);

  static String? positiveInt(String? value, [AppLocale? locale]) =>
      AppValidators.positiveInt(value, locale);

  static String? positiveDouble(String? value, [AppLocale? locale]) =>
      AppValidators.positiveNumber(value, locale);

  static String? nonNegativeDouble(String? value, [AppLocale? locale]) =>
      AppValidators.nonNegativeNumber(value, locale);

  static String? email(String? value, [AppLocale? locale]) {
    if (value == null || value.trim().isEmpty) {
      return trRead('email_required', locale ?? AppLocale.en);
    }
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!re.hasMatch(value.trim())) {
      return trRead('invalid_email', locale ?? AppLocale.en);
    }
    return null;
  }

  static String? optionalEmail(String? value, [AppLocale? locale]) =>
      AppValidators.email(value, locale);
}
