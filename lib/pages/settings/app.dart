part of 'settings_page.dart';

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("App".tl)),
        _SettingPartTitle(
          title: "Data".tl,
          icon: Icons.storage,
        ),
        ListTile(
          title: Text("Storage Path for local comics".tl),
          subtitle: Text(LocalManager().path, softWrap: false),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: LocalManager().path));
              context.showMessage(message: "Path copied to clipboard".tl);
            },
          ),
        ).toSliver(),
        _CallbackSetting(
          title: "Set New Storage Path".tl,
          actionTitle: "Set".tl,
          callback: () async {
            String? result;
            if (App.isAndroid) {
              var picker = DirectoryPicker();
              result = (await picker.pickDirectory())?.path;
            } else if (App.isIOS) {
              result = await selectDirectoryIOS();
            } else {
              result = await selectDirectory();
            }
            if (result == null) return;
            var loadingDialog = showLoadingDialog(
              App.rootContext,
              barrierDismissible: false,
              allowCancel: false,
            );
            var res = await LocalManager().setNewPath(result);
            loadingDialog.close();
            if (res != null) {
              context.showMessage(message: res);
            } else {
              context.showMessage(message: "Path set successfully".tl);
              setState(() {});
            }
          },
        ).toSliver(),
        ListTile(
          title: Text("Cache Size".tl),
          subtitle: Text(bytesToReadableString(CacheManager().currentSize)),
        ).toSliver(),
        _CallbackSetting(
          title: "Clear Cache".tl,
          actionTitle: "Clear".tl,
          callback: () async {
            var loadingDialog = showLoadingDialog(
              App.rootContext,
              barrierDismissible: false,
              allowCancel: false,
            );
            await CacheManager().clear();
            loadingDialog.close();
            context.showMessage(message: "Cache cleared".tl);
            setState(() {});
          },
        ).toSliver(),
        _CallbackSetting(
          title: "Cache Limit".tl,
          subtitle: "${appdata.settings['cacheSize']} MB",
          callback: () {
            showInputDialog(
              context: context,
              title: "Set Cache Limit".tl,
              hintText: "Size in MB".tl,
              inputValidator: RegExp(r"^\d+$"),
              onConfirm: (value) {
                appdata.settings['cacheSize'] = int.parse(value);
                appdata.saveData();
                setState(() {});
                CacheManager().setLimitSize(appdata.settings['cacheSize']);
                return null;
              },
            );
          },
          actionTitle: 'Set'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Export App Data".tl,
          callback: () async {
            var controller = showLoadingDialog(context);
            var file = await exportAppData(false);
            await saveFile(filename: "data.venera", file: file);
            controller.close();
          },
          actionTitle: 'Export'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Import App Data".tl,
          callback: () async {
            var controller = showLoadingDialog(context);
            var file = await selectFile(ext: ['venera', 'picadata']);
            if (file != null) {
              var cacheFile =
                  File(FilePath.join(App.cachePath, "import_data_temp"));
              await file.saveTo(cacheFile.path);
              try {
                if (file.name.endsWith('picadata')) {
                  await importPicaData(cacheFile);
                } else {
                  await importAppData(cacheFile);
                }
              } catch (e, s) {
                Log.error("Import data", e.toString(), s);
                context.showMessage(message: "Failed to import data".tl);
              } finally {
                cacheFile.deleteIgnoreError();
                App.forceRebuild();
              }
            }
            controller.close();
          },
          actionTitle: 'Import'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Cloud Sync".tl,
          subtitle: "WebDAV / Alist / Quark".tl,
          callback: () async {
            showPopUpWidget(context, const _CloudSyncSetting());
          },
          actionTitle: 'Set'.tl,
        ).toSliver(),
        _SettingPartTitle(
          title: "User".tl,
          icon: Icons.person_outline,
        ),
        SelectSetting(
          title: "Language".tl,
          settingKey: "language",
          optionTranslation: const {
            "system": "System",
            "zh-CN": "简体中文",
            "zh-TW": "繁體中文",
            "en-US": "English",
          },
          onChanged: () {
            App.forceRebuild();
          },
        ).toSliver(),
        if (!App.isLinux)
          _SwitchSetting(
            title: "Authorization Required".tl,
            settingKey: "authorizationRequired",
            onChanged: () async {
              var current = appdata.settings['authorizationRequired'];
              if (current) {
                final auth = LocalAuthentication();
                final bool canAuthenticateWithBiometrics =
                    await auth.canCheckBiometrics;
                final bool canAuthenticate = canAuthenticateWithBiometrics ||
                    await auth.isDeviceSupported();
                if (!canAuthenticate) {
                  context.showMessage(message: "Biometrics not supported".tl);
                  setState(() {
                    appdata.settings['authorizationRequired'] = false;
                  });
                  appdata.saveData();
                  return;
                }
              }
            },
          ).toSliver(),
      ],
    );
  }
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String logLevelToShow = "all";

  @override
  Widget build(BuildContext context) {
    var logToShow = logLevelToShow == "all"
        ? Log.logs
        : Log.logs.where((log) => log.level.name == logLevelToShow).toList();
    return Scaffold(
      appBar: Appbar(
        title: Text("Logs".tl),
        actions: [
          IconButton(
              onPressed: () => setState(() {
                    final RelativeRect position = RelativeRect.fromLTRB(
                      MediaQuery.of(context).size.width,
                      MediaQuery.of(context).padding.top + kToolbarHeight,
                      0.0,
                      0.0,
                    );
                    showMenu(context: context, position: position, items: [
                      PopupMenuItem(
                          child: Text("all"),
                          onTap: () => setState(() => logLevelToShow = "all")
                      ),
                      PopupMenuItem(
                          child: Text("info"),
                          onTap: () => setState(() => logLevelToShow = "info")
                      ),
                      PopupMenuItem(
                          child: Text("warning"),
                          onTap: () => setState(() => logLevelToShow = "warning")
                      ),
                      PopupMenuItem(
                          child: Text("error"),
                          onTap: () => setState(() => logLevelToShow = "error")
                      ),
                    ]);
              }),
              icon: const Icon(Icons.filter_list_outlined)
          ),
          IconButton(
              onPressed: () => setState(() {
                    final RelativeRect position = RelativeRect.fromLTRB(
                      MediaQuery.of(context).size.width,
                      MediaQuery.of(context).padding.top + kToolbarHeight,
                      0.0,
                      0.0,
                    );
                    showMenu(context: context, position: position, items: [
                      PopupMenuItem(
                        child: Text("Clear".tl),
                        onTap: () => setState(() => Log.clear()),
                      ),
                      PopupMenuItem(
                        child: Text("Disable Length Limitation".tl),
                        onTap: () {
                          Log.ignoreLimitation = true;
                          context.showMessage(
                              message: "Only valid for this run".tl);
                        },
                      ),
                      PopupMenuItem(
                        child: Text("Export".tl),
                        onTap: () => saveLog(Log().toString()),
                      ),
                    ]);
                  }),
              icon: const Icon(Icons.more_horiz))
        ],
      ),
      body: ListView.builder(
        reverse: true,
        controller: ScrollController(),
        itemCount: logToShow.length,
        itemBuilder: (context, index) {
          index = logToShow.length - index - 1;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(16)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(logToShow[index].title),
                        ),
                      ),
                      const SizedBox(
                        width: 3,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: [
                            Theme.of(context).colorScheme.error,
                            Theme.of(context).colorScheme.errorContainer,
                            Theme.of(context).colorScheme.primaryContainer
                          ][logToShow[index].level.index],
                          borderRadius:
                              const BorderRadius.all(Radius.circular(16)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(
                            logToShow[index].level.name,
                            style: TextStyle(
                                color: logToShow[index].level.index == 0
                                    ? Colors.white
                                    : Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(logToShow[index].content),
                  Text(logToShow[index].time
                      .toString()
                      .replaceAll(RegExp(r"\.\w+"), "")),
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: logToShow[index].content));
                    },
                    child: Text("Copy".tl),
                  ),
                  const Divider(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void saveLog(String log) async {
    saveFile(data: utf8.encode(log), filename: 'log.txt');
  }
}

class _CloudSyncSetting extends StatefulWidget {
  const _CloudSyncSetting();

  @override
  State<_CloudSyncSetting> createState() => _CloudSyncSettingState();
}

class _CloudSyncSettingState extends State<_CloudSyncSetting> {
  String provider = 'webdav';
  String url = '';
  String user = '';
  String pass = '';
  String path = '/';
  String cookie = '';
  String folderId = '0';
  String disableSync = '';

  bool autoSync = false;
  bool isTesting = false;
  bool isBusy = false;
  bool upload = true;

  @override
  void initState() {
    super.initState();
    provider = (appdata.settings['cloudProvider'] ?? 'webdav').toString();
    final cfg = appdata.settings['cloudConfig'];
    Map<String, dynamic> map = {};
    if (cfg is Map) {
      map = cfg.map((k, v) => MapEntry(k.toString(), v));
    }
    url = (map['url'] ?? '').toString();
    user = (map['user'] ?? '').toString();
    pass = (map['pass'] ?? '').toString();
    path = (map['path'] ?? (provider == 'alist' ? '/venera' : '/')).toString();
    cookie = (map['cookie'] ?? '').toString();
    folderId = (map['folderId'] ?? '0').toString();

    // Legacy WebDAV list
    if (url.isEmpty && appdata.settings['webdav'] is List) {
      final configs = appdata.settings['webdav'] as List;
      if (configs.whereType<String>().length == 3) {
        url = configs[0];
        user = configs[1];
        pass = configs[2];
      }
    }
    if (appdata.settings['disableSyncFields'].toString().trim().isNotEmpty) {
      disableSync = appdata.settings['disableSyncFields'];
    }
    autoSync = appdata.implicitData['cloudAutoSync'] ??
        appdata.implicitData['webdavAutoSync'] ??
        false;
  }

  void _persistConfig({bool clear = false}) {
    if (clear) {
      appdata.settings['cloudProvider'] = 'webdav';
      appdata.settings['cloudConfig'] = <String, dynamic>{};
      appdata.settings['webdav'] = [];
      appdata.implicitData['cloudAutoSync'] = false;
      appdata.implicitData['webdavAutoSync'] = false;
      appdata.writeImplicitData();
      appdata.saveData();
      return;
    }
    appdata.settings['cloudProvider'] = provider;
    final cfg = <String, dynamic>{
      'url': url.trim(),
      'user': user,
      'pass': pass,
      'path': path.trim().isEmpty ? '/' : path.trim(),
      'cookie': cookie,
      'folderId': folderId.trim().isEmpty ? '0' : folderId.trim(),
    };
    appdata.settings['cloudConfig'] = cfg;
    appdata.settings['disableSyncFields'] = disableSync;
    // Keep legacy webdav in sync when provider is webdav (other code paths).
    if (provider == 'webdav' && url.trim().isNotEmpty) {
      appdata.settings['webdav'] = [url.trim(), user, pass];
    }
    appdata.implicitData['cloudAutoSync'] = autoSync;
    appdata.implicitData['webdavAutoSync'] = autoSync;
    appdata.writeImplicitData();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "Cloud Sync".tl,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    selected: provider == e.$1,
                    onSelected: (_) => setState(() {
                      provider = e.$1;
                      if (provider == 'alist' &&
                          (path.isEmpty || path == '/')) {
                        path = '/venera';
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (provider == 'webdav' || provider == 'alist') ...[
              TextField(
                decoration: InputDecoration(
                  labelText: provider == 'alist'
                      ? "Alist URL".tl
                      : "URL",
                  hintText: provider == 'alist'
                      ? "https://alist.example.com"
                      : "A valid WebDav directory URL".tl,
                  border: const OutlineInputBorder(),
                ),
                controller: TextEditingController(text: url),
                onChanged: (v) => url = v,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: "Username".tl,
                  border: const OutlineInputBorder(),
                ),
                controller: TextEditingController(text: user),
                onChanged: (v) => user = v,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: "Password".tl,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                controller: TextEditingController(text: pass),
                onChanged: (v) => pass = v,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: "Remote Folder".tl,
                  hintText: provider == 'alist' ? "/venera" : "/",
                  border: const OutlineInputBorder(),
                ),
                controller: TextEditingController(text: path),
                onChanged: (v) => path = v,
              ),
              if (provider == 'webdav')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    "Tip: Alist WebDAV endpoint also works here.".tl,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (provider == 'alist')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    "Mount Baidu / 123 / Aliyun / Quark in Alist, then sync to that path.".tl,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            if (provider == 'quark') ...[
              TextField(
                decoration: InputDecoration(
                  labelText: "Cookie".tl,
                  hintText: "Paste Cookie from pan.quark.cn".tl,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
                controller: TextEditingController(text: cookie),
                onChanged: (v) => cookie = v,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: "Folder FID".tl,
                  hintText: "0 = root",
                  border: const OutlineInputBorder(),
                ),
                controller: TextEditingController(text: folderId),
                onChanged: (v) => folderId = v,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "Quark uses an unofficial web API; cookies expire. Prefer Alist mount when possible.".tl,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Skip Setting Fields (Optional)".tl,
                hintText: "field0, field1, field2, ...",
                hintStyle: TextStyle(color: Theme.of(context).hintColor),
                border: const OutlineInputBorder(),
              ),
              controller: TextEditingController(text: disableSync),
              onChanged: (v) => disableSync = v,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.sync),
              title: Text("Auto Sync Data".tl),
              contentPadding: EdgeInsets.zero,
              trailing: Switch(
                value: autoSync,
                onChanged: (v) => setState(() => autoSync = v),
              ),
            ),
            RadioGroup<bool>(
              groupValue: upload,
              onChanged: (value) {
                setState(() {
                  upload = value ?? upload;
                });
              },
              child: Row(
                children: [
                  Text("Operation".tl),
                  const Radio<bool>(value: true),
                  Text("Upload".tl),
                  const Radio<bool>(value: false),
                  Text("Download".tl),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: autoSync
                  ? Container(
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
                              "Once the operation is successful, app will automatically sync data with the server."
                                  .tl,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Button.outlined(
                    isLoading: isTesting,
                    onPressed: () async {
                      _persistConfig();
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Button.filled(
                    isLoading: isBusy,
                    onPressed: () async {
                      final empty = provider == 'quark'
                          ? cookie.trim().isEmpty
                          : url.trim().isEmpty;
                      if (empty &&
                          user.trim().isEmpty &&
                          pass.trim().isEmpty &&
                          cookie.trim().isEmpty) {
                        _persistConfig(clear: true);
                        context.showMessage(message: "Saved".tl);
                        App.rootPop();
                        return;
                      }
                      _persistConfig();
                      if (!autoSync) {
                        appdata.saveData();
                        context.showMessage(message: "Saved".tl);
                        App.rootPop();
                        return;
                      }
                      setState(() => isBusy = true);
                      final testResult = upload
                          ? await DataSync().uploadData()
                          : await DataSync().downloadData();
                      setState(() => isBusy = false);
                      if (testResult.error) {
                        context.showMessage(message: testResult.errorMessage!);
                        context.showMessage(message: "Saved Failed".tl);
                      } else {
                        appdata.saveData();
                        context.showMessage(message: "Saved".tl);
                        App.rootPop();
                      }
                    },
                    child: Text("Continue".tl),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ).paddingHorizontal(16),
      ),
    );
  }
}
