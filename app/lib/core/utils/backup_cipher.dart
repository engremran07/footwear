import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';

class BackupCipher {
  BackupCipher._();

  static const format = 'shoeserp_encrypted_backup';
  static const formatVersion = 1;
  static const _minimumPassphraseLength = 12;
  static const _iterations = 310000;
  static const _saltLength = 16;
  static const _aad = 'ShoesERP encrypted workspace backup v1';

  static final _cipher = AesGcm.with256bits();
  static final _keyDerivation = Pbkdf2.hmacSha256(
    iterations: _iterations,
    bits: 256,
  );

  static bool isEncrypted(List<int> bytes) {
    try {
      final parsed = jsonDecode(utf8.decode(bytes));
      return parsed is Map<String, dynamic> && parsed['format'] == format;
    } on FormatException {
      return false;
    }
  }

  static Future<Uint8List> encrypt({
    required List<int> clearBytes,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    final salt = SecretKeyData.random(length: _saltLength).bytes;
    final key = await _keyDerivation.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    try {
      final box = await _cipher.encrypt(
        const GZipEncoder().encodeBytes(clearBytes),
        secretKey: key,
        aad: utf8.encode(_aad),
      );
      final envelope = <String, Object>{
        'format': format,
        'version': formatVersion,
        'cipher': 'AES-256-GCM',
        'kdf': 'PBKDF2-HMAC-SHA256',
        'iterations': _iterations,
        'compression': 'gzip',
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'ciphertext': base64Encode(box.cipherText),
      };
      return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    } finally {
      key.destroy();
    }
  }

  /// Decrypts current encrypted archives and accepts legacy plaintext JSON
  /// snapshots so existing user backups remain recoverable.
  static Future<Uint8List> decrypt({
    required List<int> archiveBytes,
    required String passphrase,
  }) async {
    final parsed = jsonDecode(utf8.decode(archiveBytes));
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Backup archive is not a JSON object');
    }
    if (parsed['format'] != format) {
      if (parsed['metadata'] is Map<String, dynamic>) {
        return Uint8List.fromList(archiveBytes);
      }
      throw const FormatException('Unsupported backup archive format');
    }

    _validatePassphrase(passphrase);
    if (parsed['version'] != formatVersion ||
        parsed['cipher'] != 'AES-256-GCM' ||
        parsed['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        parsed['iterations'] != _iterations ||
        parsed['compression'] != 'gzip') {
      throw const FormatException('Unsupported backup encryption parameters');
    }

    try {
      final salt = base64Decode(parsed['salt'] as String);
      final nonce = base64Decode(parsed['nonce'] as String);
      final mac = Mac(base64Decode(parsed['mac'] as String));
      final ciphertext = base64Decode(parsed['ciphertext'] as String);
      if (salt.length != _saltLength ||
          nonce.length != _cipher.nonceLength ||
          mac.bytes.length != _cipher.macAlgorithm.macLength) {
        throw const FormatException('Invalid backup encryption envelope');
      }
      final key = await _keyDerivation.deriveKeyFromPassword(
        password: passphrase,
        nonce: salt,
      );
      try {
        final compressed = await _cipher.decrypt(
          SecretBox(ciphertext, nonce: nonce, mac: mac),
          secretKey: key,
          aad: utf8.encode(_aad),
        );
        return const GZipDecoder().decodeBytes(compressed, verify: true);
      } finally {
        key.destroy();
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Backup password is incorrect or the encrypted archive is damaged',
      );
    }
  }

  static void _validatePassphrase(String passphrase) {
    if (passphrase.trim().length < _minimumPassphraseLength) {
      throw ArgumentError(
        'Backup passphrase must contain at least 12 characters',
      );
    }
  }
}
