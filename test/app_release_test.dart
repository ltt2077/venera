import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/app_release.dart';

void main() {
  test('updates use this fork and published releases', () {
    expect(appRepository, 'ltt2077/venera');
    expect(
      appLatestReleaseApi,
      'https://api.github.com/repos/ltt2077/venera/releases/latest',
    );
    expect(hasPublishedAppUpdate({'tag_name': 'v1.7.7-glass'}, '1.7.6'), true);
    expect(hasPublishedAppUpdate({'tag_name': 'v1.7.7-glass'}, '1.7.7'), false);
    expect(hasPublishedAppUpdate({'tag_name': 'v1.7.6-glass'}, '1.7.7'), false);
  });
  test('numeric versions and build metadata are handled safely', () {
    expect(isNewerAppVersion('v1.7.10-glass', '1.7.9'), true);
    expect(isNewerAppVersion('1.7.7+177', '1.7.7'), false);
    expect(isNewerAppVersion('2.0.0', '1.99.99'), true);
    expect(isNewerAppVersion('invalid', '1.7.7'), false);
    expect(isNewerAppVersion('v1.8.0-beta', '1.7.7'), false);
  });
  test('drafts, prereleases and malformed responses are not updates', () {
    for (final release in [
      null,
      [],
      {},
      {'tag_name': 1},
      {'tag_name': 'v1.8.0-glass', 'draft': true},
      {'tag_name': 'v1.8.0-glass', 'prerelease': true},
    ]) {
      expect(hasPublishedAppUpdate(release, '1.7.7'), false);
    }
  });
}
