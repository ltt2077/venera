import 'dart:typed_data';

/// Abstraction for exporting/importing the same `.venera` app-data bundle
/// used by WebDAV sync. Credentials are supplied by the caller from settings;
/// implementations must never log full tokens/cookies.
abstract class CloudStorageProvider {
  String get id;
  String get displayName;

  /// Verify credentials / reachability.
  Future<void> testConnection();

  /// List remote data files (names only), typically `*.venera`.
  Future<List<CloudRemoteFile>> listDataFiles();

  /// Upload bytes under [remoteName] (e.g. `12345-7.venera`).
  Future<void> uploadFile(String remoteName, Uint8List bytes);

  /// Download remote file by name.
  Future<Uint8List> downloadFile(String remoteName);

  /// Delete remote file by name.
  Future<void> deleteFile(String remoteName);
}

class CloudRemoteFile {
  CloudRemoteFile({required this.name, this.size, this.modified});

  final String name;
  final int? size;
  final DateTime? modified;
}

class CloudProviderException implements Exception {
  CloudProviderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Redact secrets in log / error strings.
String redactSecret(String? value, {int keep = 4}) {
  if (value == null || value.isEmpty) return '';
  if (value.length <= keep * 2) return '***';
  return '${value.substring(0, keep)}…${value.substring(value.length - keep)}';
}
