import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/utils/backup_database.dart';

void main() {
  test(
    'online snapshot includes WAL commits without closing the live database',
    () async {
      final temp = await Directory.systemTemp.createTemp('venera-db-test-');
      final source = sqlite3.open('${temp.path}/live.db');
      try {
        source.execute('PRAGMA journal_mode=WAL');
        source.execute('PRAGMA wal_autocheckpoint=0');
        source.execute('CREATE TABLE history (id TEXT PRIMARY KEY)');
        source.execute("INSERT INTO history VALUES ('committed-in-wal')");
        final target = '${temp.path}/snapshot.db';
        await snapshotBackupDatabase('${temp.path}/live.db', target);
        validateBackupDatabase(target, 'history');
        final snapshot = sqlite3.open(target, mode: OpenMode.readOnly);
        try {
          expect(
            snapshot.select('SELECT id FROM history').single['id'],
            'committed-in-wal',
          );
          source.execute("INSERT INTO history VALUES ('after-snapshot')");
          expect(
            snapshot.select('SELECT count(*) AS n FROM history').single['n'],
            1,
          );
        } finally {
          snapshot.dispose();
        }
        expect(
          () => validateBackupDatabase(target, 'cookies'),
          throwsFormatException,
        );
      } finally {
        source.dispose();
        await temp.delete(recursive: true);
      }
    },
  );
}
