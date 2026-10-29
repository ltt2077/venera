import 'dart:io';

/// The JS runtime is shared: serialize replacements and coalesce repeat taps.
class ComicSourceUpdateQueue {
  final _active = <String, Future<void>>{};
  Future<void> _tail = Future.value();

  Future<void> run(String key, Future<void> Function() update) {
    return _active.putIfAbsent(key, () {
      final pending = _tail.then((_) => update());
      _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      return pending.whenComplete(() => _active.remove(key));
    });
  }
}

/// Validate first, then atomically replace the script beside the original.
/// Failed downloads/validation never overwrite the working source file.
Future<T> replaceComicSourceFile<T>({
  required File file,
  required String content,
  required Future<T> Function() validate,
  required Future<void> Function() restoreRuntime,
  bool Function()? isCancelled,
}) async {
  final temporary = File('${file.path}.updating');
  try {
    final candidate = await validate();
    await temporary.writeAsString(content, flush: true);
    if (isCancelled?.call() ?? false) {
      throw StateError('Source update cancelled');
    }
    await temporary.rename(file.path);
    return candidate;
  } catch (_) {
    await restoreRuntime();
    rethrow;
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
