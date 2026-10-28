import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/cloud_storage/backup_policy.dart';
import 'package:venera/utils/cloud_storage/cloud_provider.dart';

class FakeProvider implements CloudStorageProvider {
  final events = <String>[];
  bool failUpload = false;
  bool failDelete = false;
  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake';
  @override
  Future<void> testConnection() async {}
  @override
  Future<List<CloudRemoteFile>> listDataFiles() async => [];
  @override
  Future<Uint8List> downloadFile(String remoteName) async => Uint8List(0);
  @override
  Future<void> uploadFile(String remoteName, Uint8List bytes) async {
    events.add('upload:$remoteName');
    if (failUpload) throw StateError('offline');
  }

  @override
  Future<void> deleteFile(String remoteName) async {
    events.add('delete:$remoteName');
    if (failDelete) throw StateError('cleanup failed');
  }
}

void main() {
  final existing = [
    for (var i = 1; i <= 10; i++)
      CloudRemoteFile(name: '${19990 + i}-$i.venera'),
    CloudRemoteFile(name: 'manual.venera'),
  ];

  test('failed upload never deletes an existing backup', () async {
    final provider = FakeProvider()..failUpload = true;
    await expectLater(
      uploadBackupSafely(
        provider: provider,
        filename: '20000-11.venera',
        bytes: Uint8List(1),
        existing: existing,
      ),
      throwsStateError,
    );
    expect(provider.events, ['upload:20000-11.venera']);
  });

  test('successful upload precedes pruning and keeps manual files', () async {
    final provider = FakeProvider();
    await uploadBackupSafely(
      provider: provider,
      filename: '20000-11.venera',
      bytes: Uint8List(1),
      existing: existing,
    );
    expect(provider.events, [
      'upload:20000-11.venera',
      'delete:20000-10.venera',
    ]);
  });

  test(
    'cleanup failure does not turn an uploaded backup into a retry',
    () async {
      final provider = FakeProvider()..failDelete = true;
      final errors = <Object>[];
      await uploadBackupSafely(
        provider: provider,
        filename: '20000-11.venera',
        bytes: Uint8List(1),
        existing: existing,
        onCleanupError: errors.add,
      );
      expect(errors, hasLength(1));
      expect(
        provider.events.where((event) => event.startsWith('upload:')),
        hasLength(1),
      );
    },
  );

  test('revision sorting is numeric and is not reversed by server mtimes', () {
    final files = [
      CloudRemoteFile(name: '20000-9.venera', modified: DateTime(2030)),
      CloudRemoteFile(name: '20000-10.venera', modified: DateTime(2026)),
      CloudRemoteFile(name: '20000-2.venera'),
    ]..sort(compareBackups);
    expect(files.map((e) => backupVersion(e.name)), [10, 9, 2]);
    expect(backupVersion('../20000-10.venera'), -1);
  });

  test('local edits at the synced revision are uploaded', () {
    expect(
      syncDirection(localVersion: 7, remoteVersion: 7, localDirty: true),
      SyncDirection.upload,
    );
  });

  test(
    'divergent edits require a choice instead of overwriting local data',
    () {
      expect(
        syncDirection(localVersion: 7, remoteVersion: 8, localDirty: true),
        SyncDirection.conflict,
      );
    },
  );

  test(
    'clean devices can download newer remote data or skip the same revision',
    () {
      expect(
        syncDirection(localVersion: 7, remoteVersion: 8, localDirty: false),
        SyncDirection.download,
      );
      expect(
        syncDirection(localVersion: 7, remoteVersion: 7, localDirty: false),
        SyncDirection.skip,
      );
    },
  );

  test('matching versions with a newer remote timestamp can be restored', () {
    expect(
      syncDirection(
        localVersion: 7,
        remoteVersion: 7,
        localDirty: false,
        localTime: DateTime(2026),
        remoteTime: DateTime(2026, 1, 2),
      ),
      SyncDirection.download,
    );
  });
}
