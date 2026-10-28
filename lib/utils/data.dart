import 'dart:convert';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/cookie_jar.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/backup_format.dart';
import 'package:venera/utils/backup_database.dart';
import 'package:venera/utils/data_sync.dart';
import 'package:zip_flutter/zip_flutter.dart';

import 'io.dart';

Future<File> exportAppData([bool sync = true]) async {
  final staging = await Directory(App.cachePath).createTemp('venera-export-');
  final stagingPath = staging.path;
  final cacheFilePath = '$stagingPath.venera';
  final cacheFile = File(cacheFilePath);
  final dataPath = App.dataPath;
  final snapshot = jsonEncode(appdata.toJson());
  final metadata = sync
      ? null
      : jsonEncode(forkBackupMetadata(appdata.implicitData));
  try {
    await Isolate.run(() async {
      final settingsFile = File(FilePath.join(stagingPath, 'appdata.json'));
      settingsFile.writeAsStringSync(
        jsonEncode(
          appDataForBackup(
            jsonDecode(snapshot) as Map<String, dynamic>,
            sync: sync,
          ),
        ),
      );
      final zipFile = ZipFile.open(cacheFilePath);
      try {
        for (final name in ['history.db', 'local_favorite.db', 'cookie.db']) {
          final source = File(FilePath.join(dataPath, name));
          if (source.existsSync()) {
            final snapshotPath = FilePath.join(stagingPath, name);
            await snapshotBackupDatabase(source.path, snapshotPath);
            zipFile.addFile(name, snapshotPath);
          }
        }
        zipFile.addFile('appdata.json', settingsFile.path);
        if (metadata != null) {
          final extra = File(FilePath.join(stagingPath, 'venera_glass.json'))
            ..writeAsStringSync(metadata);
          zipFile.addFile('venera_glass.json', extra.path);
        }
        final sources = Directory(FilePath.join(dataPath, 'comic_source'));
        if (sources.existsSync()) {
          for (final file in sources.listSync()) {
            if (file is File) {
              zipFile.addFile('comic_source/${file.name}', file.path);
            }
          }
        }
      } finally {
        zipFile.close();
      }
    });
    return cacheFile;
  } catch (_) {
    await cacheFile.deleteIgnoreError();
    rethrow;
  } finally {
    await staging.deleteIgnoreError(recursive: true);
  }
}

bool _isImportingAppData = false;
bool get isImportingAppData => _isImportingAppData;

Future<void> importAppData(File file, [bool checkVersion = false]) =>
    restoreAppData(file, checkVersion: checkVersion);

/// Cloud downloads keep this device's sync targets. Manual imports also restore
/// the fork's cloud settings, including older fork backups without metadata.
Future<void> restoreAppData(
  File file, {
  bool checkVersion = false,
  bool restoreCloudSettings = true,
}) async {
  if (_isImportingAppData) {
    throw StateError('An app-data restore is already in progress');
  }
  if (restoreCloudSettings &&
      (DataSync.instance?.isUploading == true ||
          DataSync.instance?.isDownloading == true)) {
    throw StateError('Wait for cloud sync to finish before importing app data');
  }
  _isImportingAppData = true;
  DataSync.instance?.cancelScheduledSync();
  Directory? cacheDir;
  try {
    cacheDir = await Directory(App.cachePath).createTemp('venera-import-');
    final cacheDirPath = cacheDir.path;
    await Isolate.run(() {
      ZipFile.openAndExtract(file.path, cacheDirPath);
    });
    var historyFile = cacheDir.joinFile("history.db");
    var localFavoriteFile = cacheDir.joinFile("local_favorite.db");
    var appdataFile = cacheDir.joinFile("appdata.json");
    var cookieFile = cacheDir.joinFile("cookie.db");
    if (!await appdataFile.exists()) {
      throw const FormatException(
        'Invalid Venera backup: appdata.json is missing',
      );
    }
    final data = decodeBackupAppData(await appdataFile.readAsString());
    final extra = cacheDir.joinFile('venera_glass.json');
    final autoSync = restoreCloudSettings && await extra.exists()
        ? decodeForkAutoSync(await extra.readAsString())
        : <String, bool>{};
    await Isolate.run(() {
      for (final entry in {
        'history.db': 'history',
        'local_favorite.db': 'folder_order',
        'cookie.db': 'cookies',
      }.entries) {
        final path = FilePath.join(cacheDirPath, entry.key);
        if (File(path).existsSync()) validateBackupDatabase(path, entry.value);
      }
    });
    if (checkVersion) {
      var version = data['settings']['dataVersion'];
      if (version is int && version <= appdata.settings["dataVersion"]) {
        return;
      }
    }
    if (await historyFile.exists()) {
      HistoryManager().close();
      File(FilePath.join(App.dataPath, "history.db")).deleteIfExistsSync();
      historyFile.renameSync(FilePath.join(App.dataPath, "history.db"));
      await HistoryManager().init();
    }
    if (await localFavoriteFile.exists()) {
      LocalFavoritesManager().close();
      File(
        FilePath.join(App.dataPath, "local_favorite.db"),
      ).deleteIfExistsSync();
      localFavoriteFile.renameSync(
        FilePath.join(App.dataPath, "local_favorite.db"),
      );
      await LocalFavoritesManager().init();
    }
    if (await cookieFile.exists()) {
      final jar = SingleInstanceCookieJar.instance;
      jar?.dispose();
      File(FilePath.join(App.dataPath, "cookie.db")).deleteIfExistsSync();
      cookieFile.renameSync(FilePath.join(App.dataPath, "cookie.db"));
      if (jar != null) {
        // Keep existing network interceptors attached to the same cookie jar.
        jar.init();
      } else {
        SingleInstanceCookieJar.instance = SingleInstanceCookieJar(
          FilePath.join(App.dataPath, 'cookie.db'),
        );
      }
    }
    if (restoreCloudSettings) {
      appdata.implicitData.addAll(autoSync);
    }
    // A restored archive is already persisted; do not upload it again while
    // applying it, or overwrite cloud credentials during a cross-device sync.
    await appdata.syncData(
      data,
      sync: false,
      restoreCloudSettings: restoreCloudSettings,
    );
    var comicSourceDir = FilePath.join(cacheDirPath, "comic_source");
    if (Directory(comicSourceDir).existsSync()) {
      Directory(
        FilePath.join(App.dataPath, "comic_source"),
      ).deleteIfExistsSync(recursive: true);
      Directory(FilePath.join(App.dataPath, "comic_source")).createSync();
      for (var file in Directory(comicSourceDir).listSync()) {
        if (file is File) {
          var targetFile = FilePath.join(
            App.dataPath,
            "comic_source",
            file.name,
          );
          await file.copy(targetFile);
        }
      }
      await ComicSourceManager().reload();
    }
    appdata.implicitData.remove('cloudLocalDataMtime');
    appdata.implicitData['cloudDataDirty'] = false;
    await appdata.writeImplicitData();
  } finally {
    if (cacheDir != null) await cacheDir.deleteIgnoreError(recursive: true);
    _isImportingAppData = false;
  }
}

Future<void> importPicaData(File file) async {
  var cacheDirPath = FilePath.join(App.cachePath, 'temp_data');
  var cacheDir = Directory(cacheDirPath);
  if (cacheDir.existsSync()) {
    cacheDir.deleteSync(recursive: true);
  }
  cacheDir.createSync();
  try {
    await Isolate.run(() {
      ZipFile.openAndExtract(file.path, cacheDirPath);
    });
    var localFavoriteFile = cacheDir.joinFile("local_favorite.db");
    if (localFavoriteFile.existsSync()) {
      var db = sqlite3.open(localFavoriteFile.path);
      try {
        var folderNames = db
            .select("SELECT name FROM sqlite_master WHERE type='table';")
            .map((e) => e["name"] as String)
            .toList();
        folderNames.removeWhere(
          (e) => e == "folder_order" || e == "folder_sync",
        );
        for (var folderSyncValue in db.select("SELECT * FROM folder_sync;")) {
          var folderName = folderSyncValue["folder_name"];
          String sourceKey = folderSyncValue["key"];
          sourceKey = sourceKey.toLowerCase() == "htmanga"
              ? "wnacg"
              : sourceKey;
          // 有值就跳过
          if (LocalFavoritesManager().findLinked(folderName).$1 != null) {
            continue;
          }
          try {
            LocalFavoritesManager().linkFolderToNetwork(
              folderName,
              sourceKey,
              jsonDecode(folderSyncValue["sync_data"])["folderId"],
            );
          } catch (e, stack) {
            Log.error(e.toString(), stack);
          }
        }
        for (var folderName in folderNames) {
          if (!LocalFavoritesManager().existsFolder(folderName)) {
            LocalFavoritesManager().createFolder(folderName);
          }
          for (var comic in db.select("SELECT * FROM \"$folderName\";")) {
            LocalFavoritesManager().addComic(
              folderName,
              FavoriteItem(
                id: comic['target'],
                name: comic['name'],
                coverPath: comic['cover_path'],
                author: comic['author'],
                type: ComicType(switch (comic['type']) {
                  0 => 'picacg'.hashCode,
                  1 => 'ehentai'.hashCode,
                  2 => 'jm'.hashCode,
                  3 => 'hitomi'.hashCode,
                  4 => 'wnacg'.hashCode,
                  6 => 'nhentai'.hashCode,
                  _ => comic['type'],
                }),
                tags: comic['tags'].split(','),
              ),
            );
          }
        }
      } catch (e) {
        Log.error("Import Data", "Failed to import local favorite: $e");
      } finally {
        db.dispose();
      }
    }
    var historyFile = cacheDir.joinFile("history.db");
    if (historyFile.existsSync()) {
      var db = sqlite3.open(historyFile.path);
      try {
        for (var comic in db.select("SELECT * FROM history;")) {
          HistoryManager().addHistory(
            History.fromMap({
              "type": switch (comic['type']) {
                0 => 'picacg'.hashCode,
                1 => 'ehentai'.hashCode,
                2 => 'jm'.hashCode,
                3 => 'hitomi'.hashCode,
                4 => 'wnacg'.hashCode,
                5 => 'nhentai'.hashCode,
                _ => comic['type'],
              },
              "id": comic['target'],
              "max_page": comic["max_page"],
              "ep": comic["ep"],
              "page": comic["page"],
              "time": comic["time"],
              "title": comic["title"],
              "subtitle": comic["subtitle"],
              "cover": comic["cover"],
              "readEpisode": [comic["ep"]],
            }),
          );
        }
        List<ImageFavoritesComic> imageFavoritesComicList =
            ImageFavoriteManager().comics;
        for (var comic in db.select("SELECT * FROM image_favorites;")) {
          String sourceKey = comic["id"].split("-")[0];
          // 换名字了, 绅士漫画
          if (sourceKey.toLowerCase() == "htmanga") {
            sourceKey = "wnacg";
          }
          if (ComicSource.find(sourceKey) == null) {
            continue;
          }
          String id = comic["id"].split("-")[1];
          int page = comic["page"];
          // 章节和page是从1开始的, pica 可能有从 0 开始的, 得转一下
          int ep = comic["ep"] == 0 ? 1 : comic["ep"];
          String title = comic["title"];
          String epName = "";
          ImageFavoritesComic? tempComic = imageFavoritesComicList
              .firstWhereOrNull((e) => e.id == id && e.sourceKey == sourceKey);
          ImageFavorite curImageFavorite = ImageFavorite(
            page,
            "",
            null,
            "",
            id,
            ep,
            sourceKey,
            epName,
          );
          if (tempComic == null) {
            tempComic = ImageFavoritesComic(
              id,
              [],
              title,
              sourceKey,
              [],
              [],
              DateTime.now(),
              "",
              {},
              "",
              1,
            );
            tempComic.imageFavoritesEp = [
              ImageFavoritesEp("", ep, [curImageFavorite], epName, 1),
            ];
            imageFavoritesComicList.add(tempComic);
          } else {
            ImageFavoritesEp? tempEp = tempComic.imageFavoritesEp
                .firstWhereOrNull((e) => e.ep == ep);
            if (tempEp == null) {
              tempComic.imageFavoritesEp.add(
                ImageFavoritesEp("", ep, [curImageFavorite], epName, 1),
              );
            } else {
              // 如果已经有这个page了, 就不添加了
              if (tempEp.imageFavorites.firstWhereOrNull(
                    (e) => e.page == page,
                  ) ==
                  null) {
                tempEp.imageFavorites.add(curImageFavorite);
              }
            }
          }
        }
        for (var temp in imageFavoritesComicList) {
          ImageFavoriteManager().addOrUpdateOrDelete(
            temp,
            temp == imageFavoritesComicList.last,
          );
        }
      } catch (e, stack) {
        Log.error("Import Data", "Failed to import history: $e", stack);
      } finally {
        db.dispose();
      }
    }
  } finally {
    cacheDir.deleteIgnoreError(recursive: true);
  }
}
