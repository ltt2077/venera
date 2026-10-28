import 'dart:typed_data';

import 'cloud_provider.dart';

final _backupName = RegExp(r'^(\d+)-(\d+)\.venera$');

int backupVersion(String name) =>
    int.tryParse(_backupName.firstMatch(name)?.group(2) ?? '') ?? -1;

enum SyncDirection { upload, download, skip, conflict }

/// Detect divergent edits instead of silently replacing unsynced local data.
SyncDirection syncDirection({
  required int localVersion,
  required int remoteVersion,
  required bool localDirty,
  DateTime? localTime,
  DateTime? remoteTime,
}) {
  if (remoteVersion > localVersion) {
    return localDirty ? SyncDirection.conflict : SyncDirection.download;
  }
  if (remoteVersion >= 0 && remoteVersion < localVersion) {
    return SyncDirection.upload;
  }
  if (remoteVersion == localVersion) {
    if (localDirty) return SyncDirection.upload;
    if (localTime != null &&
        remoteTime != null &&
        remoteTime.difference(localTime).inSeconds > 2) {
      return SyncDirection.download;
    }
    return SyncDirection.skip;
  }
  // Unknown filenames have no comparable revision. Require a choice if this
  // device also has unsynced edits, otherwise prefer the existing remote data.
  return localDirty ? SyncDirection.conflict : SyncDirection.download;
}

class CloudSyncConflictException extends CloudProviderException {
  CloudSyncConflictException()
    : super(
        'Both local and cloud data changed. Export a backup, then choose Upload or Download.',
      );
}

/// Version is numeric; mtime alone can change when a server copies a backup.
int compareBackups(CloudRemoteFile a, CloudRemoteFile b) {
  final version = backupVersion(b.name).compareTo(backupVersion(a.name));
  if (version != 0) return version;
  if (a.modified != null && b.modified != null) {
    final time = b.modified!.compareTo(a.modified!);
    if (time != 0) return time;
  }
  final dayA =
      int.tryParse(_backupName.firstMatch(a.name)?.group(1) ?? '') ?? -1;
  final dayB =
      int.tryParse(_backupName.firstMatch(b.name)?.group(1) ?? '') ?? -1;
  final day = dayB.compareTo(dayA);
  return day != 0 ? day : b.name.compareTo(a.name);
}

/// Keep every existing backup until the new upload has completed successfully.
/// Only prune files owned by automatic sync, leaving manual .venera files alone.
Future<void> uploadBackupSafely({
  required CloudStorageProvider provider,
  required String filename,
  required Uint8List bytes,
  required List<CloudRemoteFile> existing,
  int keep = 10,
  void Function(Object error)? onCleanupError,
}) async {
  assert(keep > 0);
  await provider.uploadFile(filename, bytes);
  final owned = <String, CloudRemoteFile>{
    for (final file in existing)
      if (_backupName.hasMatch(file.name)) file.name: file,
    filename: CloudRemoteFile(name: filename),
  }.values.toList()..sort(compareBackups);
  final newestPerDay = <String, CloudRemoteFile>{};
  for (final file in owned) {
    final day = _backupName.firstMatch(file.name)!.group(1)!;
    newestPerDay.putIfAbsent(day, () => file);
  }
  final retained = newestPerDay.values.take(keep).map((e) => e.name).toSet()
    ..add(filename);
  for (final old in owned) {
    if (retained.contains(old.name)) continue;
    try {
      await provider.deleteFile(old.name);
    } catch (error) {
      // An uploaded backup remains a success even if retention cleanup fails.
      onCleanupError?.call(error);
    }
  }
}
