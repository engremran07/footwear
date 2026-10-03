import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/providers/database_backup_provider.dart';

void main() {
  test('only user exports create a local device copy', () {
    expect(BackupDestination.userExport.savesLocalCopy, isTrue);
    expect(BackupDestination.googleDrive.savesLocalCopy, isFalse);
  });

  test(
    'local archives are accepted only from their scoped directory',
    () async {
      final root = await Directory.systemTemp.createTemp('backup-scope-test');
      final scoped = Directory(
        '${root.path}${Platform.pathSeparator}tenant-user',
      )..createSync();
      final other = Directory('${root.path}${Platform.pathSeparator}other')
        ..createSync();
      final timestamp = DateTime.utc(2026, 10, 3);

      final owned = LocalBackupFile(
        file: File('${scoped.path}${Platform.pathSeparator}backup.shoesbackup'),
        modifiedAt: timestamp,
      );
      final foreign = LocalBackupFile(
        file: File('${other.path}${Platform.pathSeparator}backup.shoesbackup'),
        modifiedAt: timestamp,
      );

      expect(owned.isStoredIn(scoped), isTrue);
      expect(foreign.isStoredIn(scoped), isFalse);
      await root.delete(recursive: true);
    },
  );
}
