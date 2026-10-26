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
    if (isEnabled) {
      syncNow();
    }
    LocalFavoritesManager().addListener(onDataChanged);
    ComicSourceManager().addListener(onDataChanged);
    if (App.isDesktop) {
      Future.delayed(const Duration(seconds: 1), () {
        var controller = WindowFrame.of(App.rootContext);
        controller.addCloseListener(_handleWindowClose);
      });
    }
  }

  void onDataChanged() {
    if (isEnabled) {
      syncNow();
    }
  }

  bool _handleWindowClose() {
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
            CloudStorageProvider provider, CloudProfile profile)
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
            '${profile.name} (${profile.providerLabel}): ${res.errorMessage}');
        Log.warning(
            'Cloud Sync', 'profile ${profile.name} failed: ${res.errorMessage}');
      } catch (e, s) {
        Log.error('Cloud Sync', e, s);
        errors.add('${profile.name} (${profile.providerLabel}): $e');
      }
    }
    final msg = errors.join('\n');
    _lastError = msg;
    return Res<bool>.error(msg);
  }

  int _parseVersion(String name) {
    // `{day}-{version}.venera`
    final mid = name.split('-').elementAtOrNull(1)?.split('.').first;
    return int.tryParse(mid ?? '') ?? -1;
  }

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
            final up = await _doUpload(provider);
            if (up.error) return up;
            _lastSummary = SyncSummary(
              uploaded: 1,
              profileName: profile.name,
              detail: 'no remote file',
            );
            return const Res(true);
          }

          files.sort((a, b) {
            final ta = _bestRemoteTime(a);
            final tb = _bestRemoteTime(b);
            if (ta != null && tb != null) return tb.compareTo(ta);
            return b.name.compareTo(a.name);
          });
          final newest = files.first;
          final remoteVersion = _parseVersion(newest.name);
          final remoteMtime = _bestRemoteTime(newest);

          // Decide direction.
          var wantDownload = false;
          var wantUpload = false;
          var skip = false;

          if (remoteVersion > localVersion) {
            wantDownload = true;
          } else if (remoteVersion >= 0 && remoteVersion < localVersion) {
            wantUpload = true;
          } else if (remoteVersion == localVersion && remoteVersion >= 0) {
            if (remoteMtime != null && localMtime != null) {
              final diff = remoteMtime.difference(localMtime).inSeconds;
              if (diff > 2) {
                wantDownload = true;
              } else if (diff < -2) {
                wantUpload = true;
              } else {
                skip = true;
              }
            } else if (remoteMtime != null && localMtime == null) {
              // Prefer remote when we have no local stamp yet but versions match.
              skip = true;
            } else {
              skip = true;
            }
          } else {
            // Unknown remote version → compare mtime if possible, else upload.
            if (remoteMtime != null &&
                localMtime != null &&
                remoteMtime.isAfter(localMtime.add(const Duration(seconds: 2)))) {
              wantDownload = true;
            } else {
              wantUpload = true;
            }
          }

          if (skip) {
            _lastSummary = SyncSummary(
              skipped: 1,
              profileName: profile.name,
              detail: 'v$localVersion == remote',
            );
            Log.info('Data Sync', 'Smart sync skip via ${profile.name}');
            return const Res(true);
          }
          if (wantDownload) {
            final down = await _doDownload(provider, preferred: newest);
            if (down.error) return down;
            _lastSummary = SyncSummary(
              downloaded: 1,
              profileName: profile.name,
              detail: newest.name,
            );
            return const Res(true);
          }
          if (wantUpload) {
            final up = await _doUpload(provider);
            if (up.error) return up;
            _lastSummary = SyncSummary(
              uploaded: 1,
              profileName: profile.name,
              detail: 'local newer',
            );
            return const Res(true);
          }
          return const Res(true);
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

  Future<Res<bool>> _doUpload(CloudStorageProvider provider) async {
    appdata.settings['dataVersion']++;
    await appdata.saveData(false);
    var data = await exportAppData(
      appdata.settings['disableSyncFields'].toString().isNotEmpty,
    );
    var time = (DateTime.now().millisecondsSinceEpoch ~/ 86400000).toString();
    var filename = '$time-${appdata.settings['dataVersion']}.venera';

    var files = await provider.listDataFiles();
    files = files.where((e) => e.name.endsWith('.venera')).toList();
    var old = files.firstWhereOrNull((e) => e.name.startsWith("$time-"));
    if (old != null) {
      await provider.deleteFile(old.name);
    }
    if (files.length >= 10) {
      files.sort((a, b) => a.name.compareTo(b.name));
      await provider.deleteFile(files.first.name);
    }
    await provider.uploadFile(filename, await data.readAsBytes());
    data.deleteIgnoreError();
    appdata.implicitData['cloudLocalDataMtime'] =
        DateTime.now().millisecondsSinceEpoch;
    appdata.writeImplicitData();
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
      files.sort((a, b) {
        final ta = _bestRemoteTime(a);
        final tb = _bestRemoteTime(b);
        if (ta != null && tb != null) return tb.compareTo(ta);
        return b.name.compareTo(a.name);
      });
      file = files.firstWhereOrNull((e) => e.name.endsWith('.venera'));
    }
    if (file == null) {
      throw 'No data file found';
    }
    var version = _parseVersion(file.name);
    if (version >= 0) {
      var currentVersion = appdata.settings['dataVersion'];
      if (currentVersion != null &&
          version <= currentVersion &&
          preferred == null) {
        // Forced download path still respects version unless smart chose it.
        Log.info("Data Sync", 'No new data to download');
        return const Res(true);
      }
    }
    Log.info("Data Sync", "Downloading via ${provider.id}");
    var bytes = await provider.downloadFile(file.name);
    var localFile = File(FilePath.join(App.cachePath, file.name));
    await localFile.writeAsBytes(bytes);
    await importAppData(localFile, true);
    await localFile.delete();
    appdata.implicitData['cloudLocalDataMtime'] =
        (file.modified ?? DateTime.now()).millisecondsSinceEpoch;
    appdata.writeImplicitData();
    Log.info("Data Sync", "Data downloaded successfully");
    return const Res(true);
  }

  Future<Res<bool>> uploadData() async {
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
            _lastSummary =
                SyncSummary(downloaded: 1, profileName: profile.name);
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
