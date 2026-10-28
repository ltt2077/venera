import 'package:sqlite3/sqlite3.dart';

/// SQLite's online backup includes committed WAL pages, unlike a raw file copy.
Future<void> snapshotBackupDatabase(String source, String destination) async {
  final input = sqlite3.open(source, mode: OpenMode.readOnly);
  try {
    final output = sqlite3.open(destination);
    try {
      await input.backup(output, nPage: -1).drain<void>();
    } finally {
      output.dispose();
    }
  } finally {
    input.dispose();
  }
}

/// Reject corrupt or unrelated databases before any live database is replaced.
void validateBackupDatabase(String path, String requiredTable) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final check = db.select('PRAGMA quick_check');
    if (check.length != 1 ||
        check.single.values.first != 'ok' ||
        db.select(
          'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
          ['table', requiredTable],
        ).isEmpty) {
      throw FormatException('Invalid backup database: $requiredTable');
    }
  } finally {
    db.dispose();
  }
}
