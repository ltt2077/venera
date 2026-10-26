import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/cloud_storage/path_utils.dart';

void main() {
  group('normalizeWebdavEndpoint', () {
    test('strips duplicate /dav remote when URL already under /dav/folder', () {
      final e = normalizeWebdavEndpoint(
        'http://192.168.2.114:5244/dav/%E6%9D%A5',
        '/dav',
      );
      expect(e.remoteDir, '/');
      expect(e.baseUrl, 'http://192.168.2.114:5244/dav/%E6%9D%A5/');
    });

    test('keeps remote folder when URL is WebDAV root', () {
      final e = normalizeWebdavEndpoint(
        'http://192.168.2.114:5244/dav',
        '/来',
      );
      expect(e.remoteDir, '/来/');
    });
  });

  group('normalizeAlistEndpoint', () {
    test('strips /dav from pasted WebDAV URL and recovers path', () {
      final e = normalizeAlistEndpoint(
        'http://192.168.2.114:5244/dav/%E6%9D%A5',
        '/dav',
      );
      expect(e.apiBase, 'http://192.168.2.114:5244');
      expect(e.fsPath, '/来');
    });

    test('plain Alist root keeps path', () {
      final e = normalizeAlistEndpoint('http://host:5244', '/venera');
      expect(e.apiBase, 'http://host:5244');
      expect(e.fsPath, '/venera');
    });
  });
}
