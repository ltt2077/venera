/// URL / remote-path normalization for Alist WebDAV and Alist HTTP API.
///
/// Typical user mistakes that caused 404:
/// - WebDAV URL already includes `/dav/来` while Remote Folder is `/dav`
///   → client PROPFIND'd `/dav/来/dav/` (Not Found).
/// - Alist API URL pasted as the WebDAV endpoint (`…/dav/…`) instead of
///   the Alist root (`http://host:5244`).
library;

class WebdavEndpoint {
  const WebdavEndpoint({required this.baseUrl, required this.remoteDir});

  /// Client root, always ends with `/`.
  final String baseUrl;

  /// Directory passed to readDir/write, always starts and ends with `/`
  /// (except bare `/`).
  final String remoteDir;

  /// Absolute path tried (for error messages).
  String get triedPath {
    final u = Uri.tryParse(baseUrl);
    final basePath = u?.path ?? '';
    if (remoteDir == '/' || remoteDir.isEmpty) {
      return basePath.isEmpty ? '/' : basePath;
    }
    final a = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$a$remoteDir';
  }
}

class AlistEndpoint {
  const AlistEndpoint({required this.apiBase, required this.fsPath});

  /// Alist HTTP root without trailing slash (no `/dav`).
  final String apiBase;

  /// Filesystem path inside Alist (e.g. `/来` or `/venera`).
  final String fsPath;
}

String _decodePath(String path) {
  try {
    return Uri.decodeComponent(path);
  } catch (_) {
    return path;
  }
}

String _stripTrailingSlash(String s) {
  if (s.length > 1 && s.endsWith('/')) {
    return s.substring(0, s.length - 1);
  }
  return s;
}

String _ensureLeadingSlash(String s) {
  if (s.isEmpty) return '/';
  return s.startsWith('/') ? s : '/$s';
}

/// Normalize WebDAV base URL + remote folder so they do not double-join.
WebdavEndpoint normalizeWebdavEndpoint(String url, String remotePath) {
  final raw = url.trim();
  if (raw.isEmpty) {
    return const WebdavEndpoint(baseUrl: '/', remoteDir: '/');
  }

  final uri = Uri.tryParse(raw);
  var urlPath = _decodePath(uri?.path ?? '');
  urlPath = _stripTrailingSlash(urlPath);
  if (urlPath.isEmpty) urlPath = '/';

  var remote = remotePath.trim();
  if (remote.isEmpty) remote = '/';
  remote = _ensureLeadingSlash(_decodePath(remote));
  remote = _stripTrailingSlash(remote);
  if (remote.isEmpty) remote = '/';

  // URL already under Alist WebDAV (`/dav` or `/dav/…`) and Remote Folder is
  // `/dav` → user duplicated the WebDAV mount; use `/` relative to the URL.
  final urlUnderDav = urlPath == '/dav' || urlPath.startsWith('/dav/');
  if (urlUnderDav && (remote == '/dav' || remote == '/dav/')) {
    remote = '/';
  }

  // Remote folder already present as a suffix of the URL path.
  if (remote != '/' &&
      (urlPath == remote ||
          urlPath.endsWith(remote) ||
          urlPath.endsWith('/${remote.substring(1)}'))) {
    remote = '/';
  }

  // `/dav/xxx` remote while URL already includes that folder under /dav.
  if (remote.startsWith('/dav/') && urlUnderDav) {
    final after = remote.substring(4); // `/dav/foo` → `/foo`
    if (after.length > 1 &&
        (urlPath.endsWith(after) || urlPath.endsWith(after.substring(1)))) {
      remote = '/';
    } else if (urlPath == '/dav') {
      remote = after.isEmpty ? '/' : after;
    }
  }

  var base = raw;
  if (!base.endsWith('/')) base = '$base/';

  var dir = remote == '/' ? '/' : '$remote/';
  if (!dir.startsWith('/')) dir = '/$dir';

  return WebdavEndpoint(baseUrl: base, remoteDir: dir);
}

/// Normalize Alist HTTP API base + fs path. Strips a mistaken `/dav…` suffix
/// from the URL and recovers the folder path from it when useful.
AlistEndpoint normalizeAlistEndpoint(String url, String remotePath) {
  var u = url.trim();
  if (u.endsWith('/')) u = u.substring(0, u.length - 1);

  var pathFromUrl = '';
  final lower = u.toLowerCase();
  final davIdx = lower.indexOf('/dav');
  if (davIdx > 0) {
    // Only treat as WebDAV mount if `/dav` is at a path boundary.
    final afterDav = lower.substring(davIdx);
    if (afterDav == '/dav' || afterDav.startsWith('/dav/') || afterDav.startsWith('/dav?')) {
      pathFromUrl = u.substring(davIdx + 4); // may be '' or '/来'
      u = u.substring(0, davIdx);
      if (pathFromUrl.contains('?')) {
        pathFromUrl = pathFromUrl.split('?').first;
      }
      pathFromUrl = _decodePath(pathFromUrl);
      if (pathFromUrl.isEmpty) {
        pathFromUrl = '/';
      } else {
        pathFromUrl = _ensureLeadingSlash(pathFromUrl);
      }
      pathFromUrl = _stripTrailingSlash(pathFromUrl);
      if (pathFromUrl.isEmpty) pathFromUrl = '/';
    }
  }

  var p = remotePath.trim();
  if (p.isEmpty) p = pathFromUrl.isNotEmpty && pathFromUrl != '/' ? pathFromUrl : '/venera';
  p = _ensureLeadingSlash(_decodePath(p));
  p = _stripTrailingSlash(p);
  if (p.isEmpty) p = '/';

  // `/dav` is a WebDAV mount, not an Alist fs path.
  if (p == '/dav') {
    p = pathFromUrl.isNotEmpty && pathFromUrl != '/' ? pathFromUrl : '/';
  } else if (p.startsWith('/dav/')) {
    p = p.substring(4);
    if (p.isEmpty) p = '/';
  }

  // Prefer path recovered from a pasted WebDAV URL when the form still has
  // a placeholder remote folder.
  if (pathFromUrl.isNotEmpty &&
      pathFromUrl != '/' &&
      (p == '/' || p == '/venera')) {
    p = pathFromUrl;
  }

  return AlistEndpoint(apiBase: u, fsPath: p);
}

/// Join Alist fs path with a file name without producing `//`.
String joinFsPath(String dir, String name) {
  final d = _stripTrailingSlash(_ensureLeadingSlash(dir));
  final n = name.startsWith('/') ? name.substring(1) : name;
  if (d == '/') return '/$n';
  return '$d/$n';
}
