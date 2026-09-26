import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/backup_cipher.dart';

void main() {
  group('BackupCipher', () {
    test('encrypts and decrypts portable backup bytes', () async {
      final clear = Uint8List.fromList(utf8.encode('workspace backup payload'));
      final encrypted = await BackupCipher.encrypt(
        clearBytes: clear,
        passphrase: 'long portable backup phrase',
      );

      expect(BackupCipher.isEncrypted(encrypted), isTrue);
      expect(
        utf8.decode(encrypted),
        isNot(contains('workspace backup payload')),
      );
      expect(
        await BackupCipher.decrypt(
          archiveBytes: encrypted,
          passphrase: 'long portable backup phrase',
        ),
        orderedEquals(clear),
      );
    });

    test('rejects an incorrect passphrase', () async {
      final encrypted = await BackupCipher.encrypt(
        clearBytes: utf8.encode('private workspace data'),
        passphrase: 'correct portable passphrase',
      );

      await expectLater(
        BackupCipher.decrypt(
          archiveBytes: encrypted,
          passphrase: 'incorrect portable passphrase',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects tampered ciphertext', () async {
      final encrypted = await BackupCipher.encrypt(
        clearBytes: utf8.encode('private workspace data'),
        passphrase: 'correct portable passphrase',
      );
      final envelope =
          jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      final ciphertext = base64Decode(envelope['ciphertext'] as String);
      ciphertext[0] ^= 1;
      envelope['ciphertext'] = base64Encode(ciphertext);

      await expectLater(
        BackupCipher.decrypt(
          archiveBytes: utf8.encode(jsonEncode(envelope)),
          passphrase: 'correct portable passphrase',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts legacy plaintext JSON archives', () async {
      final legacy = Uint8List.fromList(
        utf8.encode(jsonEncode({'metadata': {}, 'shops': []})),
      );
      expect(
        await BackupCipher.decrypt(archiveBytes: legacy, passphrase: ''),
        orderedEquals(legacy),
      );
    });

    test('rejects short passphrases', () async {
      await expectLater(
        BackupCipher.encrypt(
          clearBytes: utf8.encode('private workspace data'),
          passphrase: 'too short',
        ),
        throwsArgumentError,
      );
    });
  });
}
