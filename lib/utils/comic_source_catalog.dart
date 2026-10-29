import 'dart:convert';

const officialComicSourceCatalog =
    'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json';

Uri comicSourceUri(String value) {
  final uri = Uri.parse(value.trim());
  if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
    throw const FormatException('Expected an HTTP(S) source URL');
  }
  return uri;
}

class ComicSourceCatalogEntry {
  const ComicSourceCatalogEntry({
    required this.name,
    required this.key,
    required this.version,
    required this.url,
    this.description,
  });

  final String name;
  final String key;
  final String version;
  final Uri url;
  final String? description;
}

List<ComicSourceCatalogEntry> parseComicSourceCatalog(String text, Uri base) {
  final data = jsonDecode(text);
  if (data is! List) {
    throw const FormatException('Comic source catalog must be a JSON list');
  }
  final entries = <ComicSourceCatalogEntry>[];
  final seen = <String>{};
  for (final row in data) {
    if (row is! Map) continue;
    final name = row['name'];
    final key = row['key'];
    final version = row['version'];
    final location = row['url'] ?? row['fileName'] ?? row['filename'];
    if (name is! String ||
        name.isEmpty ||
        key is! String ||
        !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(key) ||
        version is! String ||
        _versionParts(version) == null ||
        location is! String ||
        location.trim().isEmpty) {
      continue;
    }
    try {
      final url = comicSourceUri(base.resolve(location.trim()).toString());
      if (!seen.add(key)) continue;
      entries.add(
        ComicSourceCatalogEntry(
          name: name,
          key: key,
          version: version,
          url: url,
          description: row['description'] is String ? row['description'] : null,
        ),
      );
    } on FormatException {
      continue;
    }
  }
  if (data.isNotEmpty && entries.isEmpty) {
    throw const FormatException('No valid comic sources in catalog');
  }
  return entries;
}

RegExpMatch? _versionParts(String value) => RegExp(
  r'^(\d+)\.(\d+)\.(\d+)(?:[-.]([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
).firstMatch(value);

/// Keep Venera's historical `hotfix` suffix while tolerating invalid metadata.
bool isNewerSourceVersion(String candidate, String installed) {
  final a = _versionParts(candidate);
  final b = _versionParts(installed);
  if (a == null || b == null) return false;
  for (var i = 1; i <= 3; i++) {
    final difference = int.parse(a[i]!).compareTo(int.parse(b[i]!));
    if (difference != 0) return difference > 0;
  }
  final suffixA = a[4];
  final suffixB = b[4];
  if (suffixA == suffixB) return false;
  bool hotfix(String value) => value == 'hotfix' || value.startsWith('hotfix.');
  if (suffixA == null) return !hotfix(suffixB!);
  if (suffixB == null) return hotfix(suffixA);
  final partsA = suffixA.split('.');
  final partsB = suffixB.split('.');
  for (var i = 0; i < partsA.length && i < partsB.length; i++) {
    final numberA = int.tryParse(partsA[i]);
    final numberB = int.tryParse(partsB[i]);
    final difference = numberA != null && numberB != null
        ? numberA.compareTo(numberB)
        : numberA != null
        ? -1
        : numberB != null
        ? 1
        : partsA[i].compareTo(partsB[i]);
    if (difference != 0) return difference > 0;
  }
  return partsA.length > partsB.length;
}
