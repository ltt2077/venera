import 'package:venera/foundation/appdata.dart';

import 'alist_cloud_provider.dart';
import 'cloud_provider.dart';
import 'quark_cloud_provider.dart';
import 'webdav_cloud_provider.dart';

/// Sync mode for global preference.
enum CloudSyncMode {
  smart,
  upload,
  download,
  manual;

  static CloudSyncMode fromString(String? v) {
    switch ((v ?? 'smart').toLowerCase()) {
      case 'upload':
        return CloudSyncMode.upload;
      case 'download':
        return CloudSyncMode.download;
      case 'manual':
        return CloudSyncMode.manual;
      case 'smart':
      default:
        return CloudSyncMode.smart;
    }
  }

  String get storageValue => name;
}

/// One independently configured sync target.
class CloudProfile {
  CloudProfile({
    required this.id,
    required this.name,
    required this.provider,
    Map<String, dynamic>? config,
    this.priority = 0,
    this.enabled = true,
  }) : config = Map<String, dynamic>.from(config ?? const {});

  final String id;
  String name;

  /// `webdav` | `alist` | `quark`
  String provider;
  Map<String, dynamic> config;

  /// Lower number = tried earlier during failover.
  int priority;
  bool enabled;

  factory CloudProfile.fromJson(Map<String, dynamic> json) {
    return CloudProfile(
      id: (json['id'] ?? newProfileId()).toString(),
      name: (json['name'] ?? 'Profile').toString(),
      provider: (json['provider'] ?? 'webdav').toString(),
      config: asStringKeyMap(json['config']),
      priority: json['priority'] is int
          ? json['priority'] as int
          : int.tryParse('${json['priority']}') ?? 0,
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'config': config,
        'priority': priority,
        'enabled': enabled,
      };

  CloudProfile copy() => CloudProfile.fromJson(toJson());

  String get providerLabel {
    switch (provider) {
      case 'alist':
        return 'Alist / OpenList';
      case 'quark':
        return 'Quark';
      case 'webdav':
      default:
        return 'WebDAV';
    }
  }

  CloudStorageProvider? buildProvider() {
    switch (provider) {
      case 'alist':
        final url = (config['url'] ?? '').toString().trim();
        if (url.isEmpty) return null;
        return AlistCloudProvider(
          baseUrl: url,
          username: (config['user'] ?? '').toString(),
          password: (config['pass'] ?? '').toString(),
          remotePath: (config['path'] ?? '/venera').toString(),
        );
      case 'quark':
        final cookie = (config['cookie'] ?? '').toString().trim();
        if (cookie.isEmpty) return null;
        return QuarkCloudProvider(
          cookie: cookie,
          folderId: (config['folderId'] ?? '0').toString(),
        );
      case 'webdav':
      default:
        final url = (config['url'] ?? '').toString().trim();
        if (url.isEmpty) return null;
        return WebdavCloudProvider(
          url: url,
          user: (config['user'] ?? '').toString(),
          password: (config['pass'] ?? '').toString(),
          remotePath: (config['path'] ?? '/').toString(),
        );
    }
  }

  bool get isConfigured {
    if (provider == 'quark') {
      return (config['cookie'] ?? '').toString().trim().isNotEmpty;
    }
    return (config['url'] ?? '').toString().trim().isNotEmpty;
  }
}

String newProfileId() =>
    'p_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

Map<String, dynamic> asStringKeyMap(dynamic v) {
  if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return <String, dynamic>{};
}

/// Load / migrate / persist named sync profiles.
class CloudProfileStore {
  CloudProfileStore._();

  static List<CloudProfile> load() {
    migrateLegacyIfNeeded();
    final raw = appdata.settings['cloudProfiles'];
    if (raw is! List) return [];
    final list = <CloudProfile>[];
    for (final e in raw) {
      if (e is Map) {
        list.add(CloudProfile.fromJson(asStringKeyMap(e)));
      }
    }
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  static void save(List<CloudProfile> profiles, {bool persist = true}) {
    for (var i = 0; i < profiles.length; i++) {
      profiles[i].priority = i;
    }
    appdata.settings['cloudProfiles'] =
        profiles.map((e) => e.toJson()).toList();
    if (persist) appdata.saveData();
  }

  static String? get defaultId {
    final v = appdata.settings['cloudDefaultProfileId']?.toString();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static set defaultId(String? id) {
    appdata.settings['cloudDefaultProfileId'] = id;
  }

  static String? get activeId {
    final a = appdata.settings['cloudActiveProfileId']?.toString();
    if (a != null && a.isNotEmpty) return a;
    return defaultId;
  }

  static set activeId(String? id) {
    appdata.settings['cloudActiveProfileId'] = id;
  }

  static bool get autoFailover {
    final v = appdata.settings['cloudAutoFailover'];
    if (v is bool) return v;
    return true;
  }

  static set autoFailover(bool v) {
    appdata.settings['cloudAutoFailover'] = v;
  }

  static CloudSyncMode get syncMode =>
      CloudSyncMode.fromString(appdata.settings['cloudSyncMode']?.toString());

  static set syncMode(CloudSyncMode m) {
    appdata.settings['cloudSyncMode'] = m.storageValue;
  }

  static CloudProfile? findById(String? id, [List<CloudProfile>? list]) {
    if (id == null || id.isEmpty) return null;
    final profiles = list ?? load();
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  static CloudProfile? activeProfile() {
    final profiles = load().where((e) => e.enabled).toList();
    if (profiles.isEmpty) return null;
    return findById(activeId ?? defaultId, profiles) ?? profiles.first;
  }

  /// Active/preferred first, then remaining by priority (for failover).
  static List<CloudProfile> failoverOrder({String? preferId}) {
    final profiles =
        load().where((e) => e.enabled && e.isConfigured).toList();
    if (profiles.isEmpty) return [];
    profiles.sort((a, b) => a.priority.compareTo(b.priority));
    final prefer = preferId ?? activeId ?? defaultId;
    if (!autoFailover) {
      final one = findById(prefer, profiles) ?? profiles.first;
      return [one];
    }
    final head = <CloudProfile>[];
    final rest = <CloudProfile>[];
    for (final p in profiles) {
      if (p.id == prefer) {
        head.add(p);
      } else {
        rest.add(p);
      }
    }
    return [...head, ...rest];
  }

  static CloudProfile createBlank({String provider = 'webdav'}) {
    final n = load().length + 1;
    return CloudProfile(
      id: newProfileId(),
      name: '配置 $n',
      provider: provider,
      config: {
        'url': '',
        'user': '',
        'pass': '',
        'path': provider == 'alist' ? '/venera' : '/',
        'cookie': '',
        'folderId': '0',
      },
      priority: n - 1,
    );
  }

  /// One-time migration from single cloudConfig / legacy webdav list.
  static void migrateLegacyIfNeeded() {
    final existing = appdata.settings['cloudProfiles'];
    if (existing is List && existing.isNotEmpty) return;

    final provider =
        (appdata.settings['cloudProvider'] ?? 'webdav').toString();
    final cfg = asStringKeyMap(appdata.settings['cloudConfig']);
    var url = (cfg['url'] ?? '').toString().trim();
    var user = (cfg['user'] ?? '').toString();
    var pass = (cfg['pass'] ?? '').toString();
    var path = (cfg['path'] ?? (provider == 'alist' ? '/venera' : '/'))
        .toString();
    final cookie = (cfg['cookie'] ?? '').toString();
    final folderId = (cfg['folderId'] ?? '0').toString();

    final legacy = appdata.settings['webdav'];
    if (url.isEmpty && legacy is List && legacy.length == 3) {
      url = legacy[0].toString();
      user = legacy[1].toString();
      pass = legacy[2].toString();
    }

    final hasSomething = url.isNotEmpty || cookie.trim().isNotEmpty;
    if (!hasSomething) {
      if (existing is! List) {
        appdata.settings['cloudProfiles'] = <dynamic>[];
      }
      return;
    }

    final profile = CloudProfile(
      id: newProfileId(),
      name: provider == 'alist'
          ? 'Alist'
          : provider == 'quark'
              ? 'Quark'
              : 'WebDAV',
      provider: provider,
      config: {
        'url': url,
        'user': user,
        'pass': pass,
        'path': path,
        'cookie': cookie,
        'folderId': folderId,
      },
      priority: 0,
    );
    appdata.settings['cloudProfiles'] = [profile.toJson()];
    appdata.settings['cloudDefaultProfileId'] = profile.id;
    appdata.settings['cloudActiveProfileId'] = profile.id;
    appdata.settings['cloudSyncMode'] ??= 'smart';
    appdata.settings['cloudAutoFailover'] ??= true;
  }
}

bool cloudAutoSyncEnabled([Map<String, dynamic>? implicitData]) {
  final data = implicitData ?? appdata.implicitData;
  // An explicit new switch overrides the legacy value, including false.
  return (data['cloudAutoSync'] ?? data['webdavAutoSync']) == true;
}
