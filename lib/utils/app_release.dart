/// Only published releases from this fork are offered as application updates.
const appRepository = 'ltt2077/venera';
const appRepositoryUrl = 'https://github.com/$appRepository';
const appReleasesUrl = '$appRepositoryUrl/releases/latest';
const appLatestReleaseApi =
    'https://api.github.com/repos/$appRepository/releases/latest';

List<int>? _versionParts(String value) {
  final match = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-glass)?(?:\+\d+)?$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

bool isNewerAppVersion(String candidate, String installed) {
  final remote = _versionParts(candidate);
  final local = _versionParts(installed);
  if (remote == null || local == null) return false;
  for (var i = 0; i < remote.length; i++) {
    if (remote[i] != local[i]) return remote[i] > local[i];
  }
  return false;
}

bool hasPublishedAppUpdate(dynamic release, String installed) {
  if (release is! Map ||
      release['draft'] == true ||
      release['prerelease'] == true) {
    return false;
  }
  final tag = release['tag_name'];
  return tag is String && isNewerAppVersion(tag, installed);
}
