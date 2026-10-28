// Standalone checks for environments without a Flutter test runtime.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart';

import '../lib/utils/backup_database.dart';
import '../lib/utils/backup_format.dart';
import '../lib/utils/cloud_storage/backup_policy.dart';
import '../lib/utils/cloud_storage/cloud_provider.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class MemoryProvider implements CloudStorageProvider {
  final events = <String>[];
  bool failUpload = false;
  bool failDelete = false;
  @override
  String get id => 'memory';
  @override
  String get displayName => 'Memory';
  @override
  Future<void> testConnection() async {}
  @override
  Future<List<CloudRemoteFile>> listDataFiles() async => [];
  @override
  Future<Uint8List> downloadFile(String name) async => Uint8List(0);
  @override
  Future<void> uploadFile(String name, Uint8List bytes) async {
    events.add('upload:$name');
    if (failUpload) throw StateError('Upload failed');
  }

  @override
  Future<void> deleteFile(String name) async {
    events.add('delete:$name');
    if (failDelete) throw StateError('Cleanup failed');
  }
}

Future<void> main() async {
  var passed = 0;
  Future<void> check(String name, FutureOr<void> Function() action) async {
    await action();
    passed++;
    stdout.writeln('PASS $name');
  }

  final original = <String, dynamic>{
    'settings': <String, dynamic>{
      'dataVersion': 7,
      'readerMode': 'galleryLeftToRight',
      'liquidGlass': true,
      'liquidGlassBlur': 0.8,
      'cloudProfiles': [
        {
          'id': 'alist',
          'config': {'pass': 'private-password'},
        },
        {
          'id': 'quark',
          'config': {'cookie': 'private-cookie'},
        },
      ],
      'cloudConfig': {'pass': 'private-password'},
      'cloudActiveProfileId': 'quark',
      'cloudDefaultProfileId': 'alist',
      'cloudSyncMode': 'manual',
      'cloudAutoFailover': false,
      'webdav': ['https://example.test', 'user', 'private-password'],
      'deviceId': 'original-device',
      'disableSyncFields': '',
    },
    'searchHistory': ['fixture'],
  };
  final incoming = original['settings'] as Map<String, dynamic>;

  await check('full backup retains added settings and credentials', () {
    final decoded = decodeBackupAppData(
      jsonEncode(appDataForBackup(original, sync: false)),
    );
    require(
      jsonEncode(decoded) == jsonEncode(original),
      'Full settings changed',
    );
  });
  await check('sync strips credentials with empty custom exclusions', () {
    final sync = appDataForBackup(original, sync: true);
    final encoded = jsonEncode(sync);
    require(!encoded.contains('private-'), 'Credential leak');
    require(sync['settings']['liquidGlassBlur'] == 0.8, 'Glass settings lost');
    require(incoming.containsKey('cloudProfiles'), 'Export mutated source');
  });
  await check('custom exclusions are applied without mutating full data', () {
    final copy = appDataForBackup(original, sync: false);
    copy['settings']['disableSyncFields'] = ' readerMode, liquidGlassBlur ,';
    final sync = appDataForBackup(copy, sync: true);
    require(
      !sync['settings'].containsKey('readerMode'),
      'Custom field retained',
    );
    require(copy['settings'].containsKey('readerMode'), 'Full backup mutated');
  });
  await check('manual import restores cloud profiles', () {
    final restored = settingsForRestore(
      incoming,
      {},
      restoreCloudSettings: true,
    );
    require(restored['cloudActiveProfileId'] == 'quark', 'Active profile lost');
    require(restored['cloudAutoFailover'] == false, 'Failover lost');
    require(!restored.containsKey('deviceId'), 'Device identity overwritten');
  });
  await check('cloud import keeps destination credentials', () {
    final restored = settingsForRestore(
      incoming,
      {},
      restoreCloudSettings: false,
    );
    require(
      !restored.containsKey('cloudProfiles'),
      'Cloud profiles overwritten',
    );
    require(!restored.containsKey('webdav'), 'WebDAV credentials overwritten');
    require(restored['liquidGlassBlur'] == 0.8, 'Glass settings not synced');
  });
  await check('legacy WebDAV import prepares profile migration', () {
    final restored = settingsForRestore(
      {
        'webdav': ['https://example.test', 'u', 'p'],
      },
      {
        'cloudProfiles': [
          {'id': 'old'},
        ],
      },
      restoreCloudSettings: true,
    );
    require(
      (restored['cloudProfiles'] as List).isEmpty,
      'Old profile retained',
    );
    require(restored['cloudProvider'] == 'webdav', 'Legacy provider lost');
  });
  await check('original backup schema imports without extension', () {
    final data = decodeBackupAppData(
      '{"settings":{"dataVersion":3},"searchHistory":[]}',
    );
    require(data['settings']['dataVersion'] == 3, 'Upstream data lost');
  });
  await check('automatic sync flags round trip without runtime state', () {
    final flags = decodeForkAutoSync(
      jsonEncode(
        forkBackupMetadata({
          'cloudAutoSync': false,
          'webdavAutoSync': true,
          'cloudLocalDataMtime': 123,
        }),
      ),
    );
    require(
      flags.length == 2 &&
          flags['cloudAutoSync'] == false &&
          flags['webdavAutoSync'] == true,
      'Flags lost or runtime state leaked',
    );
  });
  for (final invalid in [
    '{}',
    '{"settings":[]}',
    '{"settings":{},"searchHistory":[1]}',
    '{"settings":{"dataVersion":"bad"}}',
    '{"settings":{"cloudProfiles":[1]}}',
  ]) {
    await check('malformed backup rejected: $invalid', () {
      try {
        decodeBackupAppData(invalid);
      } on FormatException {
        return;
      }
      throw StateError('Invalid backup accepted');
    });
  }
  await check('versions sort numerically despite server timestamps', () {
    final files = [
      CloudRemoteFile(name: '20000-9.venera', modified: DateTime(2030)),
      CloudRemoteFile(name: '20000-10.venera', modified: DateTime(2026)),
    ]..sort(compareBackups);
    require(
      backupVersion(files.first.name) == 10,
      'Lexical ordering regression',
    );
  });
  await check('dirty data at the same revision uploads', () {
    require(
      syncDirection(localVersion: 7, remoteVersion: 7, localDirty: true) ==
          SyncDirection.upload,
      'Unsynced changes skipped',
    );
  });
  await check('divergent data raises conflict', () {
    require(
      syncDirection(localVersion: 7, remoteVersion: 8, localDirty: true) ==
          SyncDirection.conflict,
      'Local edits would be overwritten',
    );
  });
  await check('clean same-version data skips', () {
    require(
      syncDirection(localVersion: 7, remoteVersion: 7, localDirty: false) ==
          SyncDirection.skip,
      'Unnecessary upload',
    );
  });
  await check('clean newer-remote data downloads', () {
    require(
      syncDirection(localVersion: 7, remoteVersion: 8, localDirty: false) ==
          SyncDirection.download,
      'New remote data skipped',
    );
  });
  final existing = [
    for (var i = 1; i <= 10; i++)
      CloudRemoteFile(name: '${19990 + i}-$i.venera'),
    CloudRemoteFile(name: 'manual.venera'),
  ];
  await check('upload failure leaves every old backup intact', () async {
    final provider = MemoryProvider()..failUpload = true;
    try {
      await uploadBackupSafely(
        provider: provider,
        filename: '20000-11.venera',
        bytes: Uint8List(1),
        existing: existing,
      );
    } on StateError {
      require(
        provider.events.length == 1 &&
            provider.events.single.startsWith('upload:'),
        'Deletion happened before upload success',
      );
      return;
    }
    throw StateError('Upload failure ignored');
  });
  await check(
    'same-day replacement happens only after upload succeeds',
    () async {
      final provider = MemoryProvider();
      await uploadBackupSafely(
        provider: provider,
        filename: '20000-11.venera',
        bytes: Uint8List(1),
        existing: existing,
      );
      require(
        provider.events.join(',') ==
            'upload:20000-11.venera,delete:20000-10.venera',
        'Retention or upload ordering wrong',
      );
    },
  );
  await check(
    'retention keeps ten days and leaves manual backups alone',
    () async {
      final provider = MemoryProvider();
      await uploadBackupSafely(
        provider: provider,
        filename: '20001-11.venera',
        bytes: Uint8List(1),
        existing: existing,
      );
      require(
        provider.events.join(',') ==
            'upload:20001-11.venera,delete:19991-1.venera',
        'Wrong oldest backup pruned',
      );
    },
  );
  await check('cleanup failure does not retry a completed upload', () async {
    final provider = MemoryProvider()..failDelete = true;
    final errors = <Object>[];
    await uploadBackupSafely(
      provider: provider,
      filename: '20000-11.venera',
      bytes: Uint8List(1),
      existing: existing,
      onCleanupError: errors.add,
    );
    require(
      errors.length == 1 && provider.events.length == 2,
      'Cleanup treated as upload failure',
    );
  });

  final temp = await Directory.systemTemp.createTemp('venera-core-check-');
  final live = sqlite3.open('${temp.path}/live.db');
  try {
    live.execute('PRAGMA journal_mode=WAL');
    live.execute('PRAGMA wal_autocheckpoint=0');
    live.execute('CREATE TABLE history (id TEXT PRIMARY KEY)');
    live.execute("INSERT INTO history VALUES ('committed-in-wal')");
    final snapshot = '${temp.path}/snapshot.db';
    await check('SQLite online backup includes committed WAL data', () async {
      await snapshotBackupDatabase('${temp.path}/live.db', snapshot);
      validateBackupDatabase(snapshot, 'history');
      final db = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        require(
          db.select('SELECT id FROM history').single['id'] ==
              'committed-in-wal',
          'WAL record missing',
        );
        live.execute("INSERT INTO history VALUES ('after-snapshot')");
        require(
          db.select('SELECT count(*) AS n FROM history').single['n'] == 1,
          'Snapshot changed after creation',
        );
      } finally {
        db.dispose();
      }
    });
    await check('unrelated database is rejected before restore', () {
      try {
        validateBackupDatabase(snapshot, 'cookies');
      } on FormatException {
        return;
      }
      throw StateError('Wrong database accepted');
    });
    await check('original ZIP layout reads with optional fork metadata', () {
      final archive = Archive();
      final entries = <String, List<int>>{
        'appdata.json': utf8.encode(
          jsonEncode(appDataForBackup(original, sync: false)),
        ),
        'history.db': File(snapshot).readAsBytesSync(),
        'venera_glass.json': utf8.encode(
          jsonEncode(forkBackupMetadata({'cloudAutoSync': true})),
        ),
      };
      for (final entry in entries.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      final decoded = ZipDecoder().decodeBytes(ZipEncoder().encode(archive));
      final settings = decoded.findFile('appdata.json')!;
      final restored = decodeBackupAppData(
        utf8.decode(settings.content as List<int>),
      );
      require(
        restored['settings']['dataVersion'] == 7 &&
            decoded.findFile('history.db') != null,
        'Original entries changed',
      );
    });
  } finally {
    live.dispose();
    await temp.delete(recursive: true);
  }
  stdout.writeln('$passed core checks passed.');
}
