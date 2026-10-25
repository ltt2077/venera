import 'package:venera/foundation/appdata.dart';

import 'alist_cloud_provider.dart';
import 'cloud_provider.dart';
import 'quark_cloud_provider.dart';
import 'webdav_cloud_provider.dart';

/// Build a [CloudStorageProvider] from current app settings.
///
/// Settings keys:
/// - `cloudProvider`: `webdav` | `alist` | `quark`
/// - `cloudConfig`: map of provider fields
/// - legacy `webdav`: `[url, user, pass]` still honored when provider is webdav
CloudStorageProvider? buildCloudProviderFromSettings() {
  final provider = (appdata.settings['cloudProvider'] ?? 'webdav').toString();
  final cfg = _asMap(appdata.settings['cloudConfig']);

  switch (provider) {
    case 'alist':
      final url = (cfg['url'] ?? '').toString().trim();
      final user = (cfg['user'] ?? '').toString();
      final pass = (cfg['pass'] ?? '').toString();
      final path = (cfg['path'] ?? '/venera').toString();
      if (url.isEmpty) return null;
      return AlistCloudProvider(
        baseUrl: url,
        username: user,
        password: pass,
        remotePath: path,
      );
    case 'quark':
      final cookie = (cfg['cookie'] ?? '').toString().trim();
      final folderId = (cfg['folderId'] ?? '0').toString();
      if (cookie.isEmpty) return null;
      return QuarkCloudProvider(cookie: cookie, folderId: folderId);
    case 'webdav':
    default:
      // Prefer cloudConfig; fall back to legacy webdav list.
      var url = (cfg['url'] ?? '').toString().trim();
      var user = (cfg['user'] ?? '').toString();
      var pass = (cfg['pass'] ?? '').toString();
      var path = (cfg['path'] ?? '/').toString();
      final legacy = appdata.settings['webdav'];
      if (url.isEmpty && legacy is List && legacy.length == 3) {
        url = legacy[0].toString();
        user = legacy[1].toString();
        pass = legacy[2].toString();
      }
      if (url.isEmpty) return null;
      return WebdavCloudProvider(
        url: url,
        user: user,
        password: pass,
        remotePath: path,
      );
  }
}

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return <String, dynamic>{};
}

bool cloudAutoSyncEnabled() {
  return appdata.implicitData['cloudAutoSync'] == true ||
      appdata.implicitData['webdavAutoSync'] == true;
}
