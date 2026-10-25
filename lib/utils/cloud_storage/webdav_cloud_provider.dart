import 'dart:typed_data';

import 'package:venera/network/app_dio.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import 'cloud_provider.dart';

class WebdavCloudProvider implements CloudStorageProvider {
  WebdavCloudProvider({
    required this.url,
    required this.user,
    required this.password,
    this.remotePath = '/',
  });

  final String url;
  final String user;
  final String password;
  final String remotePath;

  @override
  String get id => 'webdav';

  @override
  String get displayName => 'WebDAV';

  webdav.Client _client() {
    var base = url;
    if (!base.endsWith('/')) base = '$base/';
    return webdav.newClient(
      base,
      user: user,
      password: password,
      adapter: RHttpAdapter(),
    );
  }

  String get _dir {
    var p = remotePath.trim().isEmpty ? '/' : remotePath.trim();
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    return p;
  }

  @override
  Future<void> testConnection() async {
    final client = _client();
    await client.readDir(_dir);
  }

  @override
  Future<List<CloudRemoteFile>> listDataFiles() async {
    final client = _client();
    final files = await client.readDir(_dir);
    return files
        .where((e) => (e.name ?? '').endsWith('.venera'))
        .map((e) => CloudRemoteFile(name: e.name!, size: e.size))
        .toList();
  }

  @override
  Future<void> uploadFile(String remoteName, Uint8List bytes) async {
    final client = _client();
    await client.write('$_dir$remoteName', bytes);
  }

  @override
  Future<Uint8List> downloadFile(String remoteName) async {
    final client = _client();
    final data = await client.read('$_dir$remoteName');
    return Uint8List.fromList(data);
  }

  @override
  Future<void> deleteFile(String remoteName) async {
    final client = _client();
    await client.remove('$_dir$remoteName');
  }
}
