import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:venera/components/components.dart';
import 'package:venera/components/window_frame.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/utils/cloud_storage/cloud_factory.dart';
import 'package:venera/utils/cloud_storage/backup_policy.dart';
import 'package:venera/utils/cloud_storage/cloud_provider.dart';
import 'package:venera/utils/data.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/translations.dart';

import 'io.dart';

class SyncSummary {
  SyncSummary({
    this.uploaded = 0,
    this.downloaded = 0,
    this.skipped = 0,
    this.profileName,
    this.detail,
  });

  int uploaded;
  int downloaded;
  int skipped;
  String? profileName;
  String? detail;

  @override
  String toString() {
    final parts = <String>[];
    if (uploaded > 0) parts.add('↑$uploaded');
    if (downloaded > 0) parts.add('↓$downloaded');
    if (skipped > 0) parts.add('skip $skipped');
    final body = parts.isEmpty ? 'noop' : parts.join(' · ');
    if (profileName != null) return '[$profileName] $body';
    return body;
  }
}

/// Cross-device sync via WebDAV / Alist / Quark (same `.venera` bundle).
/// Supports multi-profile failover and smart mtime/version sync.
class DataSync with ChangeNotifier {
  DataSync._() {
    scheduleMicrotask(() {
      if (isEnabled && !isImportingAppData) syncNow();
    });
    LocalFavoritesManager().addListener(onDataChanged);
    ComicSourceManager().addListener(onDataChanged);
    if (App.isDesktop) {
      Future.delayed(const Duration(seconds: 1), () {
        var controller = WindowFrame.of(App.rootContext);
        controller.addCloseListener(_handleWindowClose);
      });
    }
  }

  Timer? _autoSyncTimer;
  bool _autoSyncPending = false;
  int _changeGeneration = 0;

  void onDataChanged() {
    if (isImportingAppData) return;
    _changeGeneration++;
    appdata.implicitData['cloudDataDirty'] = true;
    appdata.implicitData['cloudLocalDataMtime'] =
        DateTime.now().millisecondsSinceEpoch;
    appdata.writeImplicitData();
    if (!isEnabled) return;
    _autoSyncPending = true;
    _scheduleAutoSync();
  }

  void cancelScheduledSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _autoSyncPending = false;
  }

  void _scheduleAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(const Duration(seconds: 2), () async {
      if (!isEnabled || isImportingAppData) {
        cancelScheduledSync();
        return;
      }
      if (isUploading || isDownloading) {
        _scheduleAutoSync();
        return;
      }
      _autoSyncPending = false;
      _autoSyncTimer = null;
      await syncNow();
    });
  }

  bool _handleWindowClose() {
    if (_autoSyncPending && isEnabled) {
      cancelScheduledSync();
      syncNow();
    }
    if (_isUploading || _isDownloading) {
      _showWindowCloseDialog();
      return false;
    }
    return true;
  }

  void _showWindowCloseDialog() async {
    showLoadingDialog(
      App.rootContext,
      cancelButtonText: "Shut Down".tl,
      onCancel: () => exit(0),
      barrierDismissible: false,
      message: "Uploading data...".tl,
    );
    while (_isUploading || _isDownloading) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    exit(0);
  }

  static DataSync? instance;

  factory DataSync() => instance ?? (instance = DataSync._());

  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  bool _isUploading = false;

  bool get isUploading => _isUploading;

  bool _haveWaitingTask = false;

  String? _lastError;

  String? get lastError => _lastError;

  SyncSummary? _lastSummary;

  SyncSummary? get lastSummary => _lastSummary;

  bool get isEnabled {
    if (!cloudAutoSyncEnabled()) return false;
    return CloudProfileStore.activeProfile()?.isConfigured == true;
  }

  /// Run sync according to [CloudProfileStore.syncMode] with failover.
  Future<Res<bool>> syncNow({CloudSyncMode? mode}) async {
    final m = mode ?? CloudProfileStore.syncMode;
    switch (m) {
      case CloudSyncMode.upload:
        return uploadData();
      case CloudSyncMode.download:
        return downloadData();
      case CloudSyncMode.manual:
        return const Res(true);
      case CloudSyncMode.smart:
        return smartSync();
    }
  }

  Future<Res<bool>> _withFailover(
    Future<Res<bool>> Function(
      CloudStorageProvider provider,
      CloudProfile profile,
    )
    action,
  ) async {
    final order = CloudProfileStore.failoverOrder();
    if (order.isEmpty) {
      _lastError = 'Cloud sync not configured';
      return const Res<bool>.error('Cloud sync not configured');
    }
    final errors = <String>[];
    for (final profile in order) {
      final provider = profile.buildProvider();
      if (provider == null) {
        errors.add('${profile.name}: not configured');
        continue;
      }
      try {
        final res = await action(provider, profile);
        if (!res.error) {
          CloudProfileStore.activeId = profile.id;
          return res;
        }
        errors.add(
          '${profile.name} (${profile.providerLabel}): ${res.errorMessage}',
        );
        Log.warning(
          'Cloud Sync',
          'profile ${profile.name} failed: ${res.errorMessage}',
        );
      } on CloudSyncConflictException catch (e) {
        _lastError = e.message;
        return Res<bool>.error(e.message);
      } catch (e, s) {
        Log.error('Cloud Sync', e, s);
        errors.add('${profile.name} (${profile.providerLabel}): $e');
      }
    }
    final msg = errors.join('\n');
    _lastError = msg;
    return Res<bool>.error(msg);
  }

  int _parseVersion(String name) => backupVersion(name);

  DateTime? _bestRemoteTime(CloudRemoteFile f) {
    if (f.modified != null) return f.modified;
    // Fallback: day stamp in filename (days since epoch).
    final day = int.tryParse(f.name.split('-').first);
    if (day != null) {
      return DateTime.fromMillisecondsSinceEpoch(day * 86400000, isUtc: true);
    }
    return null;
  }

  Future<Res<bool>> smartSync() async {
    if (isImportingAppData) {
      return const Res<bool>.error('A restore is in progress');
    }
    if (_haveWaitingTask) return const Res(true);
    while (isDownloading || isUploading) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _haveWaitingTask = false;
    _isUploading = true;
    _isDownloading = true;
    _lastError = null;
    notifyListeners();
    try {
      return await _withFailover((provider, profile) async {
        try {
          var files = await provider.listDataFiles();
          files = files.where((e) => e.name.endsWith('.venera')).toList();
          final localVersion = (appdata.settings['dataVersion'] as int?) ?? 0;
          final localMtimeMs =
              appdata.implicitData['cloudLocalDataMtime'] as int?;
          final localMtime = localMtimeMs != null
              ? DateTime.fromMillisecondsSinceEpoch(localMtimeMs)
              : null;

          if (files.isEmpty) {
            final up = await _doUpload(provider, existing: files);
            if (up.error) return up;
            _lastSummary = SyncSummary(
              uploaded: 1,
              profileName: profile.name,
              detail: 'no remote file',
            );
            return const Res(true);
          }

          files.sort(compareBackups);
          final newest = files.first;
          final remoteVersion = _parseVersion(newest.name);
          final remoteMtime = _bestRemoteTime(newest);

          final direction = syncDirection(
            localVersion: localVersion,
            remoteVersion: remoteVersion,
            localDirty: appdata.implicitData['cloudDataDirty'] == true,
            localTime: localMtime,
            remoteTime: remoteMtime,
          );
          if (direction == SyncDirection.conflict) {
            throw CloudSyncConflictException();
          }

          if (direction == SyncDirection.skip) {
            _lastSummary = SyncSummary(
              skipped: 1,
              profileName: profile.name,
              detail: 'v$localVersion == remote',
            );
            Log.info('Data Sync', 'Smart sync skip via ${profile.name}');
            return const Res(true);
          }
          if (direction == SyncDirection.download) {
            final down = await _doDownload(provider, preferred: newest);
            if (down.error) return down;
            _lastSummary = SyncSummary(
              downloaded: 1,
              profileName: profile.name,
              detail: newest.name,
            );
            return const Res(true);
          }
          if (direction == SyncDirection.upload) {
            final up = await _doUpload(provider, existing: files);
            if (up.error) return up;
            _lastSummary = SyncSummary(
              uploaded: 1,
              profileName: profile.name,
              detail: 'local newer',
            );
            return const Res(true);
          }
          return const Res(true);
        } on CloudSyncConflictException {
          rethrow;
        } catch (e, s) {
          Log.error('Smart Sync', e, s);
          return Res<bool>.error(e.toString());
        }
      });
    } finally {
      _isUploading = false;
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<Res<bool>> _doUpload(
    CloudStorageProvider provider, {
    List<CloudRemoteFile>? existing,
  }) async {
    final files = existing ?? await provider.listDataFiles();
    var version = (appdata.settings['dataVersion'] as int?) ?? 0;
    for (final file in files) {
      final remoteVersion = backupVersion(file.name);
      if (remoteVersion > version) version = remoteVersion;
    }
    appdata.settings['dataVersion'] = version + 1;
    await appdata.saveData(false);
    final generation = _changeGeneration;
    final data = await exportAppData(true);
    var time = (DateTime.now().millisecondsSinceEpoch ~/ 86400000).toString();
    var filename = '$time-${appdata.settings['dataVersion']}.venera';

    try {
      await uploadBackupSafely(
        provider: provider,
        filename: filename,
        bytes: await data.readAsBytes(),
        existing: files,
        onCleanupError: (error) =>
            Log.warning('Cloud Sync', 'Backup cleanup failed: $error'),
      );
    } finally {
      await data.deleteIgnoreError();
    }
    if (_changeGeneration == generation) {
      appdata.implicitData['cloudDataDirty'] = false;
    }
    appdata.implicitData['cloudLocalDataMtime'] =
        DateTime.now().millisecondsSinceEpoch;
    await appdata.writeImplicitData();
    Log.info("Upload Data", "Data uploaded via ${provider.id}");
    return const Res(true);
  }

  Future<Res<bool>> _doDownload(
    CloudStorageProvider provider, {
    CloudRemoteFile? preferred,
  }) async {
    CloudRemoteFile? file = preferred;
    if (file == null) {
      var files = await provider.listDataFiles();
      files.sort(compareBackups);
      file = files.firstWhereOrNull((e) => e.name.endsWith('.venera'));
    }
    if (file == null) {
      throw 'No data file found';
    }
    Log.info("Data Sync", "Downloading via ${provider.id}");
    final generation = _changeGeneration;
    var bytes = await provider.downloadFile(file.name);
    if (_changeGeneration != generation) throw CloudSyncConflictException();
    final downloadDir = await Directory(
      App.cachePath,
    ).createTemp('venera-download-');
    final localFile = downloadDir.joinFile('data.venera');
    try {
      await localFile.writeAsBytes(bytes);
      // The smart direction has already been chosen; an explicit download must
      // also restore equal/older versions instead of reporting a skipped success.
      await restoreAppData(localFile, restoreCloudSettings: false);
    } finally {
      await downloadDir.deleteIgnoreError(recursive: true);
    }
    appdata.implicitData['cloudLocalDataMtime'] =
        (file.modified ?? DateTime.now()).millisecondsSinceEpoch;
    await appdata.writeImplicitData();
    Log.info("Data Sync", "Data downloaded successfully");
    return const Res(true);
  }

  Future<Res<bool>> uploadData() async {
    if (isImportingAppData) {
      return const Res<bool>.error('A restore is in progress');
    }
    if (isDownloading) return const Res(true);
    if (_haveWaitingTask) return const Res(true);
    while (isUploading) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _haveWaitingTask = false;
    _isUploading = true;
    _lastError = null;
    notifyListeners();
    try {
      final res = await _withFailover((provider, profile) async {
        try {
          final r = await _doUpload(provider);
          if (!r.error) {
            _lastSummary = SyncSummary(uploaded: 1, profileName: profile.name);
          }
          return r;
        } catch (e, s) {
          Log.error("Upload Data", e, s);
          return Res<bool>.error(e.toString());
        }
      });
      if (res.error) _lastError = res.errorMessage;
      return res;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  Future<Res<bool>> downloadData() async {
    if (isImportingAppData) {
      return const Res<bool>.error('A restore is in progress');
    }
    if (_haveWaitingTask) return const Res(true);
    while (isDownloading || isUploading) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _haveWaitingTask = false;
    _isDownloading = true;
    _lastError = null;
    notifyListeners();
    try {
      final res = await _withFailover((provider, profile) async {
        try {
          final r = await _doDownload(provider);
          if (!r.error) {
            _lastSummary = SyncSummary(
              downloaded: 1,
              profileName: profile.name,
            );
          }
          return r;
        } catch (e, s) {
          Log.error("Data Sync", e, s);
          return Res<bool>.error(e.toString());
        }
      });
      if (res.error) _lastError = res.errorMessage;
      return res;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<Res<bool>> testConnection({CloudProfile? profile}) async {
    try {
      if (profile != null) {
        final provider = profile.buildProvider();
        if (provider == null) {
          return const Res<bool>.error('Cloud sync not configured');
        }
        await provider.testConnection();
        return const Res(true);
      }
      return await _withFailover((provider, p) async {
        try {
          await provider.testConnection();
          return const Res(true);
        } catch (e) {
          return Res<bool>.error(e.toString());
        }
      });
    } catch (e, s) {
      Log.error("Cloud Sync", e, s);
      return Res<bool>.error(e.toString());
    }
  }
}
