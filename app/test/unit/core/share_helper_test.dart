import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/share_helper.dart';

void main() {
  group('normalizeWhatsAppPhone', () {
    test('strips non-digit characters', () {
      expect(
        normalizeWhatsAppPhone('+966 53-042-1571'),
        equals('966530421571'),
      );
    });
  });

  group('isValidWhatsAppPhone', () {
    test('accepts valid E.164-like phone numbers', () {
      expect(isValidWhatsAppPhone('+966530421571'), isTrue);
      expect(isValidWhatsAppPhone('923067863310'), isTrue);
    });

    test('rejects empty, short, leading-zero, and overlong numbers', () {
      expect(isValidWhatsAppPhone(''), isFalse);
      expect(isValidWhatsAppPhone('1234567'), isFalse);
      expect(isValidWhatsAppPhone('0123456789'), isFalse);
      expect(isValidWhatsAppPhone('1234567890123456'), isFalse);
    });
  });
}