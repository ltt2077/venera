import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/utils/comic_source_catalog.dart';

void main() {
  final base = Uri.parse('https://new.example/configs/index.json?token=public');
  Map<String, Object> entry(
    String key, {
    String field = 'fileName',
    String path = 'source.js',
  }) => {'name': key, 'key': key, 'version': '1.2.3', field: path};

  test(
    'relative scripts use the loaded catalog address with both filename spellings',
    () {
      final sources = parseComicSourceCatalog(
        jsonEncode([
          entry('a'),
          entry('b', field: 'filename', path: '../b.js'),
          entry('c', field: 'url', path: 'https://scripts.example/c.js'),
        ]),
        base,
      );
      expect(sources.map((e) => e.url.toString()), [
        'https://new.example/configs/source.js',
        'https://new.example/b.js',
        'https://scripts.example/c.js',
      ]);
    },
  );

  test('bad rows and duplicate keys cannot break a valid source list', () {
    final sources = parseComicSourceCatalog(
      jsonEncode([
        null,
        entry('valid'),
        entry('valid', path: 'duplicate.js'),
        entry('bad', field: 'url', path: 'file:///private/script.js'),
        {...entry('bad_version'), 'version': 'not a version'},
      ]),
      base,
    );
    expect(sources.map((e) => e.key), ['valid']);
    expect(
      () => parseComicSourceCatalog('{"error":"rate limited"}', base),
      throwsFormatException,
    );
    expect(() => parseComicSourceCatalog('[{}]', base), throwsFormatException);
    expect(parseComicSourceCatalog('[]', base), isEmpty);
  });

  test(
    'malformed versions are ignored and numeric prereleases compare correctly',
    () {
      expect(isNewerSourceVersion('1.2', '1.1.0'), false);
      expect(isNewerSourceVersion('1.2.0', 'unknown'), false);
      expect(isNewerSourceVersion('1.2.1', '1.2.0'), true);
      expect(isNewerSourceVersion('1.2.0-hotfix', '1.2.0'), true);
      expect(isNewerSourceVersion('1.2.0-hotfix.1', '1.2.0'), true);
      expect(isNewerSourceVersion('1.2.0', '1.2.0-hotfix'), false);
      expect(isNewerSourceVersion('1.2.0', '1.2.0-beta.10'), true);
      expect(isNewerSourceVersion('1.2.0-beta.10', '1.2.0-beta.2'), true);
      expect(isNewerSourceVersion('1.2.0+build.2', '1.2.0+build.1'), false);
    },
  );

  test(
    'fresh update checks replace stale badges and deletion clears a badge',
    () {
      final manager = ComicSourceManager();
      manager.updateAvailableUpdates({'source': '2.0.0'});
      expect(manager.availableUpdates, {'source': '2.0.0'});
      manager.updateAvailableUpdates({});
      expect(manager.availableUpdates, isEmpty);
      manager.updateAvailableUpdates({'source': '2.0.0'});
      manager.remove('source');
      expect(manager.availableUpdates, isEmpty);
    },
  );
}
