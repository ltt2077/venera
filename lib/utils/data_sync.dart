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

/// Cross-device sync via WebDAV / Alist / Quark (same `.venera` bundle).
class DataSync with ChangeNotifier {
  DataSync._() {
    if (isEnabled) {
      downloadData();
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
      uploadData();
    }
  }

  bool _handleWindowClose() {
    if (_isUploading) {
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
    while (_isUploading) {
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

  bool get isEnabled {
    if (!cloudAutoSyncEnabled()) return false;
    return buildCloudProviderFromSettings() != null;
  }

  CloudStorageProvider? _providerOrNull() => buildCloudProviderFromSettings();

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
      final provider = _providerOrNull();
      if (provider == null) {
        _lastError = 'Cloud sync not configured';
        return const Res.error('Cloud sync not configured');
      }
      try {
        appdata.settings['dataVersion']++;
        await appdata.saveData(false);
        var data = await exportAppData(
          appdata.settings['disableSyncFields'].toString().isNotEmpty,
        );
        var time =
            (DateTime.now().millisecondsSinceEpoch ~/ 86400000).toString();
        var filename = time;
        filename += '-';
        filename += appdata.settings['dataVersion'].toString();
        filename += '.venera';

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
        Log.info("Upload Data", "Data uploaded via ${provider.id}");
        return const Res(true);
      } catch (e, s) {
        Log.error("Upload Data", e, s);
        _lastError = e.toString();
        return Res.error(e.toString());
      }
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
      final provider = _providerOrNull();
      if (provider == null) {
        _lastError = 'Cloud sync not configured';
        return const Res.error('Cloud sync not configured');
      }
      try {
        var files = await provider.listDataFiles();
        files.sort((a, b) => b.name.compareTo(a.name));
        var file = files.firstWhereOrNull((e) => e.name.endsWith('.venera'));
        if (file == null) {
          throw 'No data file found';
        }
        var version =
            file.name.split('-').elementAtOrNull(1)?.split('.').first;
        if (version != null && int.tryParse(version) != null) {
          var currentVersion = appdata.settings['dataVersion'];
          if (currentVersion != null && int.parse(version) <= currentVersion) {
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
        Log.info("Data Sync", "Data downloaded successfully");
        return const Res(true);
      } catch (e, s) {
        Log.error("Data Sync", e, s);
        _lastError = e.toString();
        return Res.error(e.toString());
      }
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<Res<bool>> testConnection() async {
    try {
      final provider = _providerOrNull();
      if (provider == null) {
        return const Res.error('Cloud sync not configured');
      }
      await provider.testConnection();
      return const Res(true);
    } catch (e, s) {
      Log.error("Cloud Sync", e, s);
      return Res.error(e.toString());
    }
  }
}
