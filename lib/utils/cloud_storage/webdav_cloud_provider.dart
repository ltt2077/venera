import 'dart:typed_data';

import 'package:venera/network/app_dio.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import 'cloud_provider.dart';
import 'path_utils.dart';

class WebdavCloudProvider implements CloudStorageProvider {
  WebdavCloudProvider({
    required this.url,
    required this.user,
    required this.password,
    this.remotePath = '/',
  }) : endpoint = normalizeWebdavEndpoint(url, remotePath);

  final String url;
  final String user;
  final String password;
  final String remotePath;
  final WebdavEndpoint endpoint;

  @override
  String get id => 'webdav';

  @override
  String get displayName => 'WebDAV';

  webdav.Client _client() {
    return webdav.newClient(
      endpoint.baseUrl,
      user: user,
      password: password,
      adapter: RHttpAdapter(),
    );
  }

  String get _dir => endpoint.remoteDir;

  Never _fail(String op, Object e) {
    final path = endpoint.triedPath;
    throw CloudProviderException(
      'WebDAV $op failed (path=$path): $e',
    );
  }

  @override
  Future<void> testConnection() async {
    final client = _client();
    try {
      await client.readDir(_dir);
    } catch (e) {
      // If directory missing, try creating then re-list.
      try {
        await client.mkdir(_dir);
        await client.readDir(_dir);
      } catch (e2) {
        _fail('test', e2);
      }
    }
  }

  @override
  Future<List<CloudRemoteFile>> listDataFiles() async {
    final client = _client();
    try {
      final files = await client.readDir(_dir);
      return files
          .where((e) => (e.name ?? '').endsWith('.venera'))
          .map((e) => CloudRemoteFile(
                name: e.name!,
                size: e.size,
                modified: e.mTime,
              ))
          .toList();
    } catch (e) {
      _fail('list', e);
    }
  }

  @override
  Future<void> uploadFile(String remoteName, Uint8List bytes) async {
    final client = _client();
    try {
      await client.write('$_dir$remoteName', bytes);
    } catch (e) {
      _fail('upload $remoteName', e);
    }
  }

  @override
  Future<Uint8List> downloadFile(String remoteName) async {
    final client = _client();
    try {
      final data = await client.read('$_dir$remoteName');
      return Uint8List.fromList(data);
    } catch (e) {
      _fail('download $remoteName', e);
    }
  }

  @override
  Future<void> deleteFile(String remoteName) async {
    final client = _client();
    try {
      await client.remove('$_dir$remoteName');
    } catch (e) {
      _fail('delete $remoteName', e);
    }
  }
}
