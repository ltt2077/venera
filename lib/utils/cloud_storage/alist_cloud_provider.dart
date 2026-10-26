import 'dart:typed_data';

import 'package:venera/foundation/log.dart';
import 'package:venera/network/app_dio.dart';

import 'cloud_provider.dart';
import 'path_utils.dart';

/// Alist / OpenList HTTP API provider.
/// Works with many Chinese netdrives when the user mounts them in Alist.
class AlistCloudProvider implements CloudStorageProvider {
  AlistCloudProvider({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.remotePath = '/venera',
    this.token,
  }) : endpoint = normalizeAlistEndpoint(baseUrl, remotePath);

  final String baseUrl;
  final String username;
  final String password;
  final String remotePath;
  final AlistEndpoint endpoint;

  /// Cached JWT / token from login.
  String? token;

  @override
  String get id => 'alist';

  @override
  String get displayName => 'Alist / OpenList';

  String get _root => endpoint.apiBase;

  String get _path => endpoint.fsPath;

  Dio _dio() {
    return AppDio(BaseOptions(
      baseUrl: _root,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 120),
      validateStatus: (s) => s != null && s < 600,
    ));
  }

  Never _fail(String op, Object msg, {int? status}) {
    final extra = status != null ? ' status=$status' : '';
    throw CloudProviderException(
      'Alist $op failed$pathHint$extra: $msg',
    );
  }

  String get pathHint => ' (api=$_root path=$_path)';

  Future<void> _ensureToken() async {
    if (token != null && token!.isNotEmpty) return;
    final dio = _dio();
    final res = await dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    final data = res.data;
    if (data is! Map || data['code'] != 200) {
      final msg = data is Map ? data['message'] : 'HTTP ${res.statusCode}';
      _fail('login', msg, status: res.statusCode);
    }
    token = null;
    final tokenData = data['data'];
    if (tokenData is Map) {
      token = tokenData['token']?.toString();
    }
    if (token == null || token!.isEmpty) {
      _fail('login', 'empty token', status: res.statusCode);
    }
    Log.info('CloudSync', 'Alist login ok (token=${redactSecret(token)})');
  }

  Map<String, String> get _auth => {'Authorization': token ?? ''};

  Future<bool> _listOk(Dio dio) async {
    final res = await dio.post(
      '/api/fs/list',
      data: {'path': _path, 'page': 1, 'per_page': 1},
      options: Options(headers: _auth),
    );
    final data = res.data;
    return data is Map && data['code'] == 200;
  }

  @override
  Future<void> testConnection() async {
    token = null;
    await _ensureToken();
    final dio = _dio();
    if (await _listOk(dio)) return;

    final mkdir = await dio.post(
      '/api/fs/mkdir',
      data: {'path': _path},
      options: Options(headers: _auth),
    );
    if (await _listOk(dio)) return;

    final msg = mkdir.data is Map
        ? mkdir.data['message']
        : 'HTTP ${mkdir.statusCode}';
    _fail('list/mkdir', msg ?? 'not found', status: mkdir.statusCode);
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
      final msg = data is Map ? data['message'] : 'HTTP ${res.statusCode}';
      _fail('list', msg ?? 'error', status: res.statusCode);
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
    final fullPath = joinFsPath(_path, remoteName);
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
      _fail('upload $remoteName', data['message'] ?? 'error',
          status: res.statusCode);
    }
    if (res.statusCode != null && res.statusCode! >= 400) {
      _fail('upload $remoteName', 'HTTP ${res.statusCode}',
          status: res.statusCode);
    }
  }

  @override
  Future<Uint8List> downloadFile(String remoteName) async {
    await _ensureToken();
    final dio = _dio();
    final fullPath = joinFsPath(_path, remoteName);
    final meta = await dio.post(
      '/api/fs/get',
      data: {'path': fullPath},
      options: Options(headers: _auth),
    );
    dynamic rawUrl;
    if (meta.data is Map) {
      if (meta.data['code'] != null && meta.data['code'] != 200) {
        _fail('get $remoteName', meta.data['message'] ?? 'error',
            status: meta.statusCode);
      }
      final d = meta.data['data'];
      if (d is Map) rawUrl = d['raw_url'];
    }
    if (rawUrl is! String || rawUrl.isEmpty) {
      _fail('get $remoteName', 'missing raw_url', status: meta.statusCode);
    }
    final fileRes = await dio.get<List<int>>(
      rawUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    if (fileRes.statusCode != null && fileRes.statusCode! >= 400) {
      _fail('download $remoteName', 'HTTP ${fileRes.statusCode}',
          status: fileRes.statusCode);
    }
    return Uint8List.fromList(fileRes.data ?? const []);
  }

  @override
  Future<void> deleteFile(String remoteName) async {
    await _ensureToken();
    final dio = _dio();
    final res = await dio.post(
      '/api/fs/remove',
      data: {
        'dir': _path,
        'names': [remoteName],
      },
      options: Options(headers: _auth),
    );
    if (res.data is Map &&
        res.data['code'] != null &&
        res.data['code'] != 200) {
      _fail('delete $remoteName', res.data['message'] ?? 'error',
          status: res.statusCode);
    }
  }
}
