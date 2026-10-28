import 'dart:convert';

/// Device settings kept out of cross-device sync, including cloud credentials.
const deviceOnlySettings = <String>{
  'proxy',
  'authorizationRequired',
  'customImageProcessing',
  'webdav',
  'cloudProvider',
  'cloudConfig',
  'cloudProfiles',
  'cloudDefaultProfileId',
  'cloudActiveProfileId',
  'cloudAutoFailover',
  'cloudSyncMode',
  'disableSyncFields',
  'deviceId',
};

/// The fork's settings that a manual backup restores on the receiving device.
const cloudBackupSettings = <String>{
  'webdav',
  'cloudProvider',
  'cloudConfig',
  'cloudProfiles',
  'cloudDefaultProfileId',
  'cloudActiveProfileId',
  'cloudAutoFailover',
  'cloudSyncMode',
};

Map<String, dynamic> settingsForRestore(
  Map<String, dynamic> incoming,
  Map<String, dynamic> local, {
  required bool restoreCloudSettings,
}) {
  final excluded = excludedSyncSettings(
    (local['disableSyncFields'] ?? '').toString(),
  );
  final restored = <String, dynamic>{
    for (final entry in incoming.entries)
      if (!excluded.contains(entry.key) ||
          (restoreCloudSettings && cloudBackupSettings.contains(entry.key)))
        entry.key: entry.value,
  };
  if (restoreCloudSettings &&
      !incoming.containsKey('cloudProfiles') &&
      (incoming.containsKey('cloudConfig') ||
          (incoming['webdav'] is List &&
              (incoming['webdav'] as List).length == 3))) {
    // Original and early fork backups need migration, not the receiver's old
    // named profiles. The legacy connection is migrated on the next load.
    restored['cloudProfiles'] = <dynamic>[];
    restored['cloudDefaultProfileId'] = null;
    restored['cloudActiveProfileId'] = null;
    if (!incoming.containsKey('cloudConfig')) {
      restored['cloudConfig'] = <String, dynamic>{};
      restored['cloudProvider'] = 'webdav';
    }
  }
  return restored;
}

Set<String> excludedSyncSettings(String customFields) => {
  ...deviceOnlySettings,
  ...customFields.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
};

/// Preserve the original appdata.json schema; only remove device-only fields.
Map<String, dynamic> appDataForBackup(
  Map<String, dynamic> data, {
  required bool sync,
}) {
  final copy = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  if (sync) {
    final settings = copy['settings'] as Map<String, dynamic>;
    final excluded = excludedSyncSettings(
      (settings['disableSyncFields'] ?? '').toString(),
    );
    settings.removeWhere((key, _) => excluded.contains(key));
  }
  return copy;
}

/// Validate before replacing any live databases.
Map<String, dynamic> decodeBackupAppData(String content) {
  final data = jsonDecode(content);
  if (data is! Map<String, dynamic> ||
      data['settings'] is! Map<String, dynamic>) {
    throw const FormatException('Invalid Venera backup: settings are missing');
  }
  final history = data['searchHistory'];
  if (history != null &&
      (history is! List || history.any((entry) => entry is! String))) {
    throw const FormatException('Invalid Venera backup: search history');
  }
  final settings = data['settings'] as Map<String, dynamic>;
  final version = settings['dataVersion'];
  if (version != null && (version is! int || version < 0)) {
    throw const FormatException('Invalid Venera backup: data version');
  }
  final profiles = settings['cloudProfiles'];
  if (profiles != null &&
      (profiles is! List ||
          profiles.any(
            (entry) =>
                entry is! Map ||
                (entry['config'] != null && entry['config'] is! Map),
          ))) {
    throw const FormatException('Invalid Venera backup: cloud profiles');
  }
  return data;
}

/// Optional extra ZIP entry. Upstream ignores it and keeps its original schema.
Map<String, dynamic> forkBackupMetadata(Map<String, dynamic> implicitData) => {
  'formatVersion': 1,
  'autoSync': {
    for (final key in ['cloudAutoSync', 'webdavAutoSync'])
      if (implicitData[key] is bool) key: implicitData[key],
  },
};

Map<String, bool> decodeForkAutoSync(String content) {
  final data = jsonDecode(content);
  if (data is! Map || data['formatVersion'] != 1 || data['autoSync'] is! Map) {
    throw const FormatException('Unsupported Venera Glass backup metadata');
  }
  final flags = data['autoSync'] as Map;
  return {
    for (final key in ['cloudAutoSync', 'webdavAutoSync'])
      if (flags[key] is bool) key: flags[key] as bool,
  };
}
