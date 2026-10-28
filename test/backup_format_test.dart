import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/backup_format.dart';

void main() {
  Map<String, dynamic> fixture() => {
    'settings': {
      'dataVersion': 7,
      'readerMode': 'continuousTopToBottom',
      'liquidGlass': true,
      'liquidGlassBlur': 0.8,
      'liquidGlassQuality': 'minimal',
      'cloudProfiles': [
        {
          'id': 'alist',
          'provider': 'alist',
          'config': {'url': 'https://example.test', 'pass': 'secret'},
        },
        {
          'id': 'quark',
          'provider': 'quark',
          'config': {'cookie': 'private-cookie'},
        },
      ],
      'cloudDefaultProfileId': 'alist',
      'cloudActiveProfileId': 'quark',
      'cloudAutoFailover': false,
      'cloudSyncMode': 'manual',
      'cloudConfig': {'pass': 'legacy-secret'},
      'webdav': ['https://example.test/dav', 'user', 'secret'],
      'deviceId': 'this-device',
      'disableSyncFields': '',
    },
    'searchHistory': ['test'],
  };

  test('manual backup preserves added settings and cloud credentials', () {
    final data = fixture();
    final restored = decodeBackupAppData(
      jsonEncode(appDataForBackup(data, sync: false)),
    );
    expect(restored, data);
  });

  test('sync always removes device fields even with no custom exclusions', () {
    final original = fixture();
    final sync = appDataForBackup(original, sync: true);
    final settings = sync['settings'] as Map;
    for (final key in deviceOnlySettings) {
      expect(settings.containsKey(key), false, reason: key);
    }
    expect(settings['liquidGlassBlur'], 0.8);
    expect(settings['liquidGlassQuality'], 'minimal');
    expect((original['settings'] as Map)['cloudProfiles'], isNotEmpty);
    expect(jsonEncode(sync), isNot(contains('secret')));
    expect(jsonEncode(sync), isNot(contains('private-cookie')));
  });

  test('custom sync exclusions do not change the full backup', () {
    final data = fixture();
    data['settings']['disableSyncFields'] = ' liquidGlassBlur, readerMode , ,';
    final sync = appDataForBackup(data, sync: true);
    expect(sync['settings'].containsKey('liquidGlassBlur'), false);
    expect(sync['settings'].containsKey('readerMode'), false);
    expect(
      appDataForBackup(data, sync: false)['settings']['liquidGlassBlur'],
      0.8,
    );
  });

  test(
    'manual restore applies fork profiles and cloud restore keeps this device',
    () {
      final incoming = fixture()['settings'] as Map<String, dynamic>;
      final local = <String, dynamic>{
        'cloudProfiles': [],
        'deviceId': 'receiver',
        'disableSyncFields': 'readerMode',
      };
      final manual = settingsForRestore(
        incoming,
        local,
        restoreCloudSettings: true,
      );
      expect(manual['cloudActiveProfileId'], 'quark');
      expect(manual['cloudSyncMode'], 'manual');
      expect(manual.containsKey('deviceId'), false);
      expect(manual['readerMode'], 'continuousTopToBottom');
      final sync = settingsForRestore(
        incoming,
        local,
        restoreCloudSettings: false,
      );
      expect(sync.containsKey('cloudProfiles'), false);
      expect(sync.containsKey('webdav'), false);
      expect(sync['liquidGlassBlur'], 0.8);
    },
  );

  test('original WebDAV backup resets profiles for legacy migration', () {
    final restored = settingsForRestore(
      {
        'webdav': ['https://example.test/dav', 'user', 'pass'],
      },
      {
        'cloudProfiles': [
          {'id': 'old'},
        ],
      },
      restoreCloudSettings: true,
    );
    expect(restored['cloudProfiles'], isEmpty);
    expect(restored['cloudProvider'], 'webdav');
    expect(restored['cloudConfig'], isEmpty);
    expect(restored['webdav'], ['https://example.test/dav', 'user', 'pass']);
  });

  test('upstream appdata schema needs no fork metadata', () {
    final data = decodeBackupAppData(
      '{"settings":{"dataVersion":3,"readerMode":"galleryLeftToRight"},'
      '"searchHistory":["upstream"]}',
    );
    expect(data['settings']['dataVersion'], 3);
    expect(data['searchHistory'], ['upstream']);
  });

  test('optional metadata preserves only automatic sync flags', () {
    final flags = decodeForkAutoSync(
      jsonEncode(
        forkBackupMetadata({
          'cloudAutoSync': false,
          'webdavAutoSync': true,
          'cloudLocalDataMtime': 123,
          'unrelatedDeviceSetting': 'private',
        }),
      ),
    );
    expect(flags, {'cloudAutoSync': false, 'webdavAutoSync': true});
  });

  test('invalid settings and search history fail preflight', () {
    for (final content in [
      '{}',
      '{"settings":[]}',
      '{"settings":{},"searchHistory":[1]}',
      '{"settings":{"dataVersion":"7"}}',
      '{"settings":{"cloudProfiles":["invalid"]}}',
    ]) {
      expect(() => decodeBackupAppData(content), throwsFormatException);
    }
  });
}
