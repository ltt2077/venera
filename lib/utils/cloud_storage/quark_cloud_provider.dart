import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/app_dio.dart';

import 'cloud_provider.dart';

/// Quark (夸克网盘) provider via the public web drive API.
///
/// Headless OAuth is impractical; the user pastes a browser Cookie string
/// (from pan.quark.cn while logged in) plus an optional folder fid.
///
/// API surface is unofficial and may break — treat as best-effort.
class QuarkCloudProvider implements CloudStorageProvider {
  QuarkCloudProvider({
    required this.cookie,
    this.folderId = '0',
  });

  final String cookie;
  final String folderId;

  static const _api = 'https://drive-pc.quark.cn';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  @override
  String get id => 'quark';

  @override
  String get displayName => 'Quark';

  Dio _dio() {
    return AppDio(BaseOptions(
      baseUrl: _api,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 180),
      headers: {
        'Cookie': cookie,
        'User-Agent': _ua,
        'Referer': 'https://pan.quark.cn/',
        'Origin': 'https://pan.quark.cn',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
      },
      validateStatus: (s) => s != null && s < 500,
    ));
  }

  void _check(dynamic data, String op) {
    if (data is! Map) {
      throw CloudProviderException('Quark $op: invalid response');
    }
    final status = data['status'];
    final code = data['code'];
    final message = data['message'];
    if (status != null && status != 200 && status != 0) {
      throw CloudProviderException(
        'Quark $op failed (status=$status, code=$code): $message',
      );
    }
    if (code != null && code != 0 && status == null) {
      throw CloudProviderException(
        'Quark $op failed (code=$code): $message',
      );
    }
  }

  @override
  Future<void> testConnection() async {
    if (cookie.trim().isEmpty) {
      throw CloudProviderException('Quark cookie is empty');
    }
    Log.info('CloudSync', 'Quark test (cookie=${redactSecret(cookie)})');
    final dio = _dio();
    final res = await dio.get(
      '/1/clouddrive/config',
      queryParameters: {'pr': 'ucpro', 'fr': 'pc'},
    );
    _check(res.data, 'config');
    await listDataFiles();
  }

  @override
  Future<List<CloudRemoteFile>> listDataFiles() async {
    final dio = _dio();
    final res = await dio.post(
      '/1/clouddrive/file/sort',
      queryParameters: {'pr': 'ucpro', 'fr': 'pc'},
      data: {
        'pdir_fid': folderId,
        '_page': 1,
        '_size': 100,
        '_sort': 'file_type:asc,updated_at:desc',
      },
    );
    _check(res.data, 'list');
    dynamic list;
    if (res.data is Map) {
      final d = res.data['data'];
      if (d is Map) list = d['list'];
    }
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .where((e) => (e['file_name']?.toString() ?? '').endsWith('.venera'))
        .map((e) => CloudRemoteFile(
              name: e['file_name'].toString(),
              size: e['size'] is int
                  ? e['size'] as int
                  : int.tryParse(e['size'].toString()),
            ))
        .toList();
  }

  Future<String?> _findFid(String name) async {
    final dio = _dio();
    final res = await dio.post(
      '/1/clouddrive/file/sort',
      queryParameters: {'pr': 'ucpro', 'fr': 'pc'},
      data: {
        'pdir_fid': folderId,
        '_page': 1,
        '_size': 100,
        '_sort': 'file_type:asc,updated_at:desc',
      },
    );
    dynamic list;
    if (res.data is Map) {
      final d = res.data['data'];
      if (d is Map) list = d['list'];
    }
    if (list is! List) return null;
    for (final e in list.whereType<Map>()) {
      if (e['file_name']?.toString() == name) {
        return e['fid']?.toString();
      }
    }
    return null;
  }

  @override
  Future<void> uploadFile(String remoteName, Uint8List bytes) async {
    final dio = _dio();
    final md5sum = md5.convert(bytes).toString();
    final sha1sum = sha1.convert(bytes).toString();

    final existing = await _findFid(remoteName);
    if (existing != null) {
      await _deleteFid(existing);
    }

    final pre = await dio.post(
      '/1/clouddrive/file/upload/pre',
      queryParameters: {'pr': 'ucpro', 'fr': 'pc'},
      data: {
        'ccp_hash_update': true,
        'parallel_upload': true,
        'pdir_fid': folderId,
        'dir_name': '',
        'size': bytes.length,
        'file_name': remoteName,
        'format_type': 'application/octet-stream',
        'md5': md5sum,
        'sha1': sha1sum,
      },
    );
    _check(pre.data, 'upload/pre');
    final data = pre.data is Map ? pre.data['data'] as Map? : null;
    if (data == null) {
      throw CloudProviderException('Quark upload/pre empty data');
    }

    if (data['finish'] == true) {
      Log.info('CloudSync', 'Quark instant upload ok for $remoteName');
      return;
    }

    final taskId = data['task_id']?.toString();
    final uploadId = data['upload_id']?.toString();
    final bucket = data['bucket']?.toString();
    final objKey = data['obj_key']?.toString();
    String? uploadUrl = data['upload_url']?.toString();
    final authInfo = data['auth_info'];
    if ((uploadUrl == null || uploadUrl.isEmpty) && authInfo is Map) {
      uploadUrl = authInfo['upload_url']?.toString();
    }

    if (uploadUrl != null && uploadUrl.isNotEmpty) {
      final put = await AppDio().put(
        uploadUrl,
        data: bytes,
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Length': bytes.length,
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (put.statusCode != null && put.statusCode! >= 400) {
        throw CloudProviderException(
          'Quark PUT failed: HTTP ${put.statusCode}',
        );
      }
    } else if (taskId != null) {
      Log.info(
        'CloudSync',
        'Quark upload metadata task=$taskId uploadId=$uploadId '
        'bucket=$bucket key=$objKey (direct URL missing — finish only)',
      );
    }

    final finish = await dio.post(
      '/1/clouddrive/file/upload/finish',
      queryParameters: {'pr': 'ucpro', 'fr': 'pc'},
      data: {
        'obj_key': objKey,
        'task_id': taskId,
        'md5': md5sum,
        'sha1': sha1sum,
        'bucket': bucket,
        'callback': data['callback'] ?? {},
        'upload_id': uploadId,
      },
    );
    _check(finish.data, 'upload/finish');
  }

  @override
  Future<Uint8List> downloadFile(String remoteName) async {
    final fid = await _findFid(remoteName);
    if (fid == null) {
      throw CloudProviderException('Quark file not found: $remoteName');
    }
    final dio = _dio();
    final res = await dio.post(
      '/1/clouddrive/file/download',
      queryParameters: {'pr': 'ucpro', 'fr': 'pc'},
      data: {
        'fids': [fid],
      },
    );
    _check(res.data, 'download');
    final list = res.data is Map ? res.data['data'] : null;
    String? url;
    if (list is List && list.isNotEmpty) {
      url = list.first['download_url']?.toString();
    } else if (list is Map) {
      url = list['download_url']?.toString();
    }
    if (url == null || url.isEmpty) {
      throw CloudProviderException('Quark download_url missing');
    }
    final fileRes = await AppDio().get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'Cookie': cookie,
          'User-Agent': _ua,
          'Referer': 'https://pan.quark.cn/',
        },
      ),
    );
    return Uint8List.fromList(fileRes.data ?? const []);
  }

  Future<void> _deleteFid(String fid) async {
    final dio = _dio();
    await dio.post(
      '/1/clouddrive/file/delete',
      queryParameters: {'pr': 'ucpro', 'fr': 'pc'},
      data: {
        'action_type': 2,
        'filelist': [
          {'fid': fid}
        ],
        'exclude_fids': [],
      },
    );
  }

  @override
  Future<void> deleteFile(String remoteName) async {
    final fid = await _findFid(remoteName);
    if (fid == null) return;
    await _deleteFid(fid);
  }
}
