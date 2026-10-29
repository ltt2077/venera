import 'dart:io';

/// Validate first, then atomically replace the script beside the original.
/// Failed downloads/validation never overwrite the working source file.
Future<T> replaceComicSourceFile<T>({
  required File file,
  required String content,
  required Future<T> Function() validate,
  required Future<void> Function() restoreRuntime,
}) async {
  final temporary = File('${file.path}.updating');
  try {
    final candidate = await validate();
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
    return candidate;
  } catch (_) {
    await restoreRuntime();
    rethrow;
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
