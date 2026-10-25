import 'dart:typed_data';

import 'package:venera/foundation/log.dart';
import 'package:venera/network/app_dio.dart';

import 'cloud_provider.dart';

/// Alist / OpenList HTTP API provider.
/// Works with many Chinese netdrives when the user mounts them in Alist.
class AlistCloudProvider implements CloudStorageProvider {
  AlistCloudProvider({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.remotePath = '/venera',
    this.token,
  });

  final String baseUrl;
  final String username;
  final String password;
  final String remotePath;

  /// Cached JWT / token from login.
  String? token;

  @override
  String get id => 'alist';

  @override
  String get displayName => 'Alist / OpenList';

  String get _root {
    var u = baseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  String get _path {
    var p = remotePath.trim().isEmpty ? '/' : remotePath.trim();
    if (!p.startsWith('/')) p = '/$p';
    if (p.endsWith('/') && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  Dio _dio() {
    return AppDio(BaseOptions(
      baseUrl: _root,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 120),
      validateStatus: (s) => s != null && s < 500,
    ));
  }

  Future<void> _ensureToken() async {
    if (token != null && token!.isNotEmpty) return;
    final dio = _dio();
    final res = await dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    final data = res.data;
    if (data is! Map || data['code'] != 200) {
      final msg = data is Map ? data['message'] : res.statusCode;
      throw CloudProviderException('Alist login failed: $msg');
    }
    token = null;
    final tokenData = data['data'];
    if (tokenData is Map) {
      token = tokenData['token']?.toString();
    }
    if (token == null || token!.isEmpty) {
      throw CloudProviderException('Alist login returned empty token');
    }
    Log.info('CloudSync', 'Alist login ok (token=${redactSecret(token)})');
  }

  Map<String, String> get _auth => {'Authorization': token ?? ''};

  @override
  Future<void> testConnection() async {
    token = null;
    await _ensureToken();
    final dio = _dio();
    final res = await dio.post(
      '/api/fs/list',
      data: {'path': _path, 'page': 1, 'per_page': 1},
      options: Options(headers: _auth),
    );
    final data = res.data;
    if (data is! Map || data['code'] != 200) {
      await dio.post(
        '/api/fs/mkdir',
        data: {'path': _path},
        options: Options(headers: _auth),
      );
      final res2 = await dio.post(
        '/api/fs/list',
        data: {'path': _path, 'page': 1, 'per_page': 1},
        options: Options(headers: _auth),
      );
      if (res2.data is! Map || res2.data['code'] != 200) {
        final msg =
            res2.data is Map ? res2.data['message'] : res2.statusCode;
        throw CloudProviderException('Alist list failed: $msg');
      }
    }
  }

  @override
  Future<List<CloudRemoteFile>> listDataFiles() async {
    await _ensureToken();
    final dio = _dio();
    final res = await dio.post(
      '/api/fs/list',
      data: {'path': _path, 'page': 1, 'per_page': 100},
      options: Options(headers: _auth),
    );
    final data = res.data;
    if (data is! Map || data['code'] != 200) {
      final msg = data is Map ? data['message'] : res.statusCode;
      throw CloudProviderException('Alist list failed: $msg');
    }
    dynamic content;
    final contentData = data['data'];
    if (contentData is Map) {
      content = contentData['content'];
    }
    if (content is! List) return [];
    return content
        .whereType<Map>()
        .where((e) => (e['name']?.toString() ?? '').endsWith('.venera'))
        .map((e) => CloudRemoteFile(
              name: e['name'].toString(),
              size: e['size'] is int
                  ? e['size'] as int
                  : int.tryParse(e['size'].toString()),
              modified: e['modified'] != null
                  ? DateTime.tryParse(e['modified'].toString())
                  : null,
            ))
        .toList();
  }

  @override
  Future<void> uploadFile(String remoteName, Uint8List bytes) async {
    await _ensureToken();
    final dio = _dio();
    final fullPath = '$_path/$remoteName';
    final res = await dio.put(
      '/api/fs/put',
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          ..._auth,
          'File-Path': Uri.encodeComponent(fullPath),
          'Content-Type': 'application/octet-stream',
          'Content-Length': bytes.length,
        },
      ),
    );
    final data = res.data;
    if (data is Map && data['code'] != null && data['code'] != 200) {
      final msg = data["message"];
      throw CloudProviderException("Alist upload failed: $msg");
    }
  }

  @override
  Future<Uint8List> downloadFile(String remoteName) async {
    await _ensureToken();
    final dio = _dio();
    final fullPath = '$_path/$remoteName';
    final meta = await dio.post(
      '/api/fs/get',
      data: {'path': fullPath},
      options: Options(headers: _auth),
    );
    dynamic rawUrl;
    if (meta.data is Map) {
      final d = meta.data['data'];
      if (d is Map) rawUrl = d['raw_url'];
    }
    if (rawUrl is! String || rawUrl.isEmpty) {
      throw CloudProviderException('Alist get raw_url failed for $remoteName');
    }
    final fileRes = await dio.get<List<int>>(
      rawUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(fileRes.data ?? const []);
  }

  @override
  Future<void> deleteFile(String remoteName) async {
    await _ensureToken();
    final dio = _dio();
    await dio.post(
      '/api/fs/remove',
      data: {
        'dir': _path,
        'names': [remoteName],
      },
      options: Options(headers: _auth),
    );
  }
}
