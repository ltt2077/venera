part of 'settings_page.dart';

/// Multi-profile Cloud Sync settings (WebDAV / Alist / Quark).
class CloudSyncSettingPage extends StatefulWidget {
  const CloudSyncSettingPage({super.key});

  @override
  State<CloudSyncSettingPage> createState() => _CloudSyncSettingPageState();
}

class _CloudSyncSettingPageState extends State<CloudSyncSettingPage> {
  late List<CloudProfile> profiles;
  late CloudSyncMode syncMode;
  late bool autoFailover;
  late bool autoSync;
  String? defaultId;
  String? activeId;
  String disableSync = '';

  bool isTesting = false;
  bool isBusy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    CloudProfileStore.migrateLegacyIfNeeded();
    profiles = CloudProfileStore.load().map((e) => e.copy()).toList();
    syncMode = CloudProfileStore.syncMode;
    autoFailover = CloudProfileStore.autoFailover;
    defaultId = CloudProfileStore.defaultId;
    activeId = CloudProfileStore.activeId;
    autoSync = appdata.implicitData['cloudAutoSync'] ??
        appdata.implicitData['webdavAutoSync'] ??
        false;
    if (appdata.settings['disableSyncFields'].toString().trim().isNotEmpty) {
      disableSync = appdata.settings['disableSyncFields'];
    }
  }

  void _persist({bool saveFile = true}) {
    CloudProfileStore.save(profiles, persist: false);
    CloudProfileStore.defaultId = defaultId;
    CloudProfileStore.activeId = activeId;
    CloudProfileStore.syncMode = syncMode;
    CloudProfileStore.autoFailover = autoFailover;
    appdata.settings['disableSyncFields'] = disableSync;
    appdata.implicitData['cloudAutoSync'] = autoSync;
    appdata.implicitData['webdavAutoSync'] = autoSync;
    appdata.writeImplicitData();
    // Keep legacy keys roughly in sync for older code paths.
    final active = CloudProfileStore.findById(activeId, profiles) ??
        CloudProfileStore.findById(defaultId, profiles);
    if (active != null) {
      appdata.settings['cloudProvider'] = active.provider;
      appdata.settings['cloudConfig'] = Map<String, dynamic>.from(active.config);
      if (active.provider == 'webdav') {
        final url = (active.config['url'] ?? '').toString();
        if (url.isNotEmpty) {
          appdata.settings['webdav'] = [
            url,
            active.config['user'] ?? '',
            active.config['pass'] ?? '',
          ];
        }
      }
    }
    if (saveFile) appdata.saveData();
  }

  Future<void> _editProfile(CloudProfile profile, {bool isNew = false}) async {
    final result = await showPopUpWidget<CloudProfile?>(
      context,
      _CloudProfileEditor(profile: profile.copy(), isNew: isNew),
    );
    if (result == null) return;
    setState(() {
      final idx = profiles.indexWhere((e) => e.id == result.id);
      if (idx >= 0) {
        profiles[idx] = result;
      } else {
        profiles.add(result);
      }
      defaultId ??= result.id;
      activeId ??= result.id;
    });
    _persist();
  }

  void _movePriority(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= profiles.length) return;
    setState(() {
      final item = profiles.removeAt(index);
      profiles.insert(next, item);
    });
    _persist();
  }

  Future<void> _runSync() async {
    _persist();
    setState(() => isBusy = true);
    final res = await DataSync().syncNow(mode: syncMode == CloudSyncMode.manual
        ? CloudSyncMode.smart
        : syncMode);
    setState(() => isBusy = false);
    if (res.error) {
      context.showMessage(message: res.errorMessage!);
    } else {
      final summary = DataSync().lastSummary;
      context.showMessage(
        message: summary != null
            ? '${"Sync OK".tl}: $summary'
            : "Sync OK".tl,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "Cloud Sync".tl,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text("Profiles".tl, style: ts.s16.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            "Each profile is independent. Set a Default, reorder for failover priority, and switch Active anytime."
                .tl,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text("No profiles yet. Tap Add.".tl),
            ),
          for (var i = 0; i < profiles.length; i++)
            _profileTile(profiles[i], i),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button.outlined(
                onPressed: () async {
                  final p = CloudProfileStore.createBlank();
                  await _editProfile(p, isNew: true);
                },
                child: Text("Add Profile".tl),
              ),
              Button.outlined(
                isLoading: isTesting,
                onPressed: () async {
                  if (profiles.isEmpty) {
                    context.showMessage(message: "No profiles yet. Tap Add.".tl);
                    return;
                  }
                  _persist();
                  setState(() => isTesting = true);
                  final res = await DataSync().testConnection();
                  setState(() => isTesting = false);
                  if (res.error) {
                    context.showMessage(message: res.errorMessage!);
                  } else {
                    context.showMessage(message: "Connection OK".tl);
                  }
                },
                child: Text("Test".tl),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text("Sync".tl, style: ts.s16.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text("Sync Mode".tl, style: ts.s14),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final m in CloudSyncMode.values)
                ChoiceChip(
                  label: Text(_modeLabel(m).tl),
                  selected: syncMode == m,
                  onSelected: (_) => setState(() => syncMode = m),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Smart compares local dataVersion / mtime with remote Last-Modified and picks upload or download."
                .tl,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync),
            title: Text("Auto Sync Data".tl),
            trailing: Switch(
              value: autoSync,
              onChanged: (v) => setState(() => autoSync = v),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alt_route),
            title: Text("Auto Failover".tl),
            subtitle: Text(
              "On failure, try the next profile in priority order.".tl,
            ),
            trailing: Switch(
              value: autoFailover,
              onChanged: (v) => setState(() => autoFailover = v),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              labelText: "Skip Setting Fields (Optional)".tl,
              hintText: "field0, field1, field2, ...",
              border: const OutlineInputBorder(),
            ),
            controller: TextEditingController(text: disableSync),
            onChanged: (v) => disableSync = v,
          ),
          const SizedBox(height: 16),
          if (autoSync)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Once saved, the app will automatically sync with the active profile (and failover if enabled)."
                          .tl,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Button.outlined(
                  isLoading: isBusy && syncMode == CloudSyncMode.download,
                  onPressed: () async {
                    _persist();
                    setState(() => isBusy = true);
                    final res = await DataSync().downloadData();
                    setState(() => isBusy = false);
                    if (res.error) {
                      context.showMessage(message: res.errorMessage!);
                    } else {
                      context.showMessage(message: "Download OK".tl);
                    }
                  },
                  child: Text("Download".tl),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Button.outlined(
                  isLoading: isBusy && syncMode == CloudSyncMode.upload,
                  onPressed: () async {
                    _persist();
                    setState(() => isBusy = true);
                    final res = await DataSync().uploadData();
                    setState(() => isBusy = false);
                    if (res.error) {
                      context.showMessage(message: res.errorMessage!);
                    } else {
                      context.showMessage(message: "Upload OK".tl);
                    }
                  },
                  child: Text("Upload".tl),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Button.filled(
                  isLoading: isBusy,
                  onPressed: () async {
                    _persist();
                    if (!autoSync && syncMode == CloudSyncMode.manual) {
                      context.showMessage(message: "Saved".tl);
                      App.rootPop();
                      return;
                    }
                    if (autoSync || syncMode != CloudSyncMode.manual) {
                      await _runSync();
                      if (DataSync().lastError == null) {
                        App.rootPop();
                      }
                    } else {
                      context.showMessage(message: "Saved".tl);
                      App.rootPop();
                    }
                  },
                  child: Text(
                    syncMode == CloudSyncMode.manual && !autoSync
                        ? "Save".tl
                        : "Save & Sync".tl,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _modeLabel(CloudSyncMode m) {
    switch (m) {
      case CloudSyncMode.smart:
        return 'Smart';
      case CloudSyncMode.upload:
        return 'Upload';
      case CloudSyncMode.download:
        return 'Download';
      case CloudSyncMode.manual:
        return 'Manual';
    }
  }

  Widget _profileTile(CloudProfile p, int index) {
    final isDefault = p.id == defaultId;
    final isActive = p.id == activeId;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _editProfile(p),
        title: Row(
          children: [
            Expanded(
              child: Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDefault)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.star,
                    size: 16, color: Theme.of(context).colorScheme.primary),
              ),
            if (isActive)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text("Active".tl, style: const TextStyle(fontSize: 10)),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '#${index + 1} · ${p.providerLabel}'
          '${p.isConfigured ? '' : ' · ${"incomplete".tl}'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: "Priority up".tl,
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: () => _movePriority(index, -1),
            ),
            IconButton(
              tooltip: "Priority down".tl,
              icon: const Icon(Icons.arrow_downward, size: 18),
              onPressed: () => _movePriority(index, 1),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'default') {
                  setState(() => defaultId = p.id);
                  _persist();
                } else if (v == 'active') {
                  setState(() => activeId = p.id);
                  _persist();
                  context.showMessage(message: "${"Switched to".tl} ${p.name}");
                } else if (v == 'toggle') {
                  setState(() => p.enabled = !p.enabled);
                  _persist();
                } else if (v == 'delete') {
                  setState(() {
                    profiles.removeWhere((e) => e.id == p.id);
                    if (defaultId == p.id) {
                      defaultId =
                          profiles.isEmpty ? null : profiles.first.id;
                    }
                    if (activeId == p.id) {
                      activeId = defaultId;
                    }
                  });
                  _persist();
                } else if (v == 'edit') {
                  await _editProfile(p);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'active', child: Text("Use / Switch".tl)),
                PopupMenuItem(value: 'default', child: Text("Set Default".tl)),
                PopupMenuItem(value: 'edit', child: Text("Edit".tl)),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(p.enabled ? "Disable".tl : "Enable".tl),
                ),
                PopupMenuItem(value: 'delete', child: Text("Delete".tl)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudProfileEditor extends StatefulWidget {
  const _CloudProfileEditor({required this.profile, this.isNew = false});

  final CloudProfile profile;
  final bool isNew;

  @override
  State<_CloudProfileEditor> createState() => _CloudProfileEditorState();
}

class _CloudProfileEditorState extends State<_CloudProfileEditor> {
  late CloudProfile profile;
  late TextEditingController nameCtrl;
  late TextEditingController urlCtrl;
  late TextEditingController userCtrl;
  late TextEditingController passCtrl;
  late TextEditingController pathCtrl;
  late TextEditingController cookieCtrl;
  late TextEditingController folderCtrl;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    profile = widget.profile;
    nameCtrl = TextEditingController(text: profile.name);
    urlCtrl = TextEditingController(text: (profile.config['url'] ?? '').toString());
    userCtrl = TextEditingController(text: (profile.config['user'] ?? '').toString());
    passCtrl = TextEditingController(text: (profile.config['pass'] ?? '').toString());
    pathCtrl = TextEditingController(
        text: (profile.config['path'] ??
                (profile.provider == 'alist' ? '/venera' : '/'))
            .toString());
    cookieCtrl =
        TextEditingController(text: (profile.config['cookie'] ?? '').toString());
    folderCtrl = TextEditingController(
        text: (profile.config['folderId'] ?? '0').toString());
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    urlCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    pathCtrl.dispose();
    cookieCtrl.dispose();
    folderCtrl.dispose();
    super.dispose();
  }

  void _applyFields() {
    profile.name = nameCtrl.text.trim().isEmpty ? profile.name : nameCtrl.text.trim();
    profile.config['url'] = urlCtrl.text.trim();
    profile.config['user'] = userCtrl.text;
    profile.config['pass'] = passCtrl.text;
    profile.config['path'] =
        pathCtrl.text.trim().isEmpty ? '/' : pathCtrl.text.trim();
    profile.config['cookie'] = cookieCtrl.text;
    profile.config['folderId'] =
        folderCtrl.text.trim().isEmpty ? '0' : folderCtrl.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: widget.isNew ? "Add Profile".tl : "Edit Profile".tl,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(
              labelText: "Name".tl,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text("Provider".tl, style: ts.s14),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final e in [
                ('webdav', 'WebDAV'),
                ('alist', 'Alist / OpenList'),
                ('quark', 'Quark'),
              ])
                ChoiceChip(
                  label: Text(e.$2),
                  selected: profile.provider == e.$1,
                  onSelected: (_) => setState(() {
                    profile.provider = e.$1;
                    if (e.$1 == 'alist' &&
                        (pathCtrl.text.isEmpty || pathCtrl.text == '/')) {
                      pathCtrl.text = '/venera';
                    }
                    if (e.$1 == 'webdav' && pathCtrl.text == '/venera') {
                      pathCtrl.text = '/';
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (profile.provider == 'webdav' || profile.provider == 'alist') ...[
            TextField(
              controller: urlCtrl,
              decoration: InputDecoration(
                labelText: profile.provider == 'alist'
                    ? "Alist URL".tl
                    : "URL",
                hintText: profile.provider == 'alist'
                    ? "http://192.168.1.1:5244"
                    : "http://host:5244/dav/folder",
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: userCtrl,
              decoration: InputDecoration(
                labelText: "Username".tl,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Password".tl,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pathCtrl,
              decoration: InputDecoration(
                labelText: "Remote Folder".tl,
                hintText: profile.provider == 'alist' ? "/来 or /venera" : "/",
                border: const OutlineInputBorder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                profile.provider == 'webdav'
                    ? "Tip: If the URL already ends with the folder (e.g. /dav/来), leave Remote Folder as /. Do not set Remote Folder to /dav."
                        .tl
                    : "Use Alist root URL (no /dav). Remote Folder is the Alist path (e.g. /来). Pasting a WebDAV URL is auto-normalized."
                        .tl,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (profile.provider == 'quark') ...[
            TextField(
              controller: cookieCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: "Cookie".tl,
                hintText: "Paste Cookie from pan.quark.cn".tl,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: folderCtrl,
              decoration: InputDecoration(
                labelText: "Folder FID".tl,
                hintText: "0 = root",
                border: const OutlineInputBorder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                "Quark uses an unofficial web API; cookies expire. Prefer Alist mount when possible."
                    .tl,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Button.outlined(
                  isLoading: testing,
                  onPressed: () async {
                    _applyFields();
                    setState(() => testing = true);
                    final res = await DataSync().testConnection(profile: profile);
                    setState(() => testing = false);
                    if (res.error) {
                      context.showMessage(message: res.errorMessage!);
                    } else {
                      context.showMessage(message: "Connection OK".tl);
                    }
                  },
                  child: Text("Test".tl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Button.filled(
                  onPressed: () {
                    _applyFields();
                    context.pop(profile);
                  },
                  child: Text("Save".tl),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
