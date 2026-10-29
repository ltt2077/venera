import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/comic_source_update.dart';

void main() {
  late Directory directory;
  late File script;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('source-update-test');
    script = File('${directory.path}/source.js');
    await script.writeAsString('working source');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'invalid update preserves the working file and restores runtime',
    () async {
      var restored = false;
      await expectLater(
        replaceComicSourceFile(
          file: script,
          content: 'invalid source',
          validate: () async =>
              throw const FormatException('Invalid source key'),
          restoreRuntime: () async {
            restored = true;
          },
        ),
        throwsFormatException,
      );
      expect(await script.readAsString(), 'working source');
      expect(restored, true);
      expect(await File('${script.path}.updating').exists(), false);
    },
  );

  test(
    'write failure preserves the old script and removes the temporary file',
    () async {
      // A directory at the temporary path makes a write fail on all platforms.
      final blocker = await Directory('${script.path}.updating').create();
      var restored = false;
      await expectLater(
        replaceComicSourceFile(
          file: script,
          content: 'new source',
          validate: () async => 'validated',
          restoreRuntime: () async {
            restored = true;
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await script.readAsString(), 'working source');
      expect(restored, true);
      await blocker.delete();
    },
  );

  test(
    'validated update replaces the existing file and returns the candidate',
    () async {
      var restored = false;
      final candidate = await replaceComicSourceFile(
        file: script,
        content: 'updated source',
        validate: () async {
          expect(await script.readAsString(), 'working source');
          return 'candidate';
        },
        restoreRuntime: () async {
          restored = true;
        },
      );
      expect(candidate, 'candidate');
      expect(await script.readAsString(), 'updated source');
      expect(await File('${script.path}.updating').exists(), false);
      expect(restored, false);
    },
  );
}
