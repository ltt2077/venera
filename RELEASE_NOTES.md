# Venera Glass fork — 1.7.1+171

Fork of archived [venera-app/venera](https://github.com/venera-app/venera) (last upstream v1.6.3).
GPL-3.0. No bundled comic sources.

## 1.7.1 fixes (Android glass · Alist 404 · multi-profile · smart sync)

### Android 液态玻璃 / Liquid glass
- Lower Android fill opacity + higher blur σ so frosted chrome is visibly glassy (not solid Material white).
- Pop-up sheets / Cloud Sync scaffold use translucent GlassSurface; BackdropFilter tile mode tuned for Android Impeller.

### Alist / WebDAV 404
- Normalize WebDAV URL vs Remote Folder (no more `/dav/来` + Remote `/dav` → PROPFIND `/dav/来/dav/` 404).
- Alist HTTP API strips a pasted `/dav/…` WebDAV URL down to the Alist root and recovers the folder path.
- Clearer errors: status + path tried.

### Multi-profile sync
- Named profiles (WebDAV / Alist / Quark), each with its own credentials.
- Manual **Default** + **Active** switch anytime.
- Priority order (↑↓) + **Auto Failover** (default ON): on failure try the next profile.
- Sync mode: **Smart** (default) | Upload | Download | Manual.
- Smart: compare local `dataVersion` / mtime with remote Last-Modified / filename day stamp; newer wins; equal → skip. Summary shown after sync.

### 中文摘要
- 修复 Android 液态玻璃几乎看不出（过实心）的问题。
- 修复 Alist WebDAV 与 Alist API 因路径重复拼接导致的 404。
- 支持多个同步配置独立保存、手动选默认/切换、失败按优先级自动尝试。
- 新增智能同步：按服务器文件修改时间与本地版本决定上传或下载覆盖。

## Liquid Glass UI (default ON)

Settings → Appearance → **Liquid Glass**. Classic opaque chrome remains when toggled off.

| Platform | Approach |
|----------|----------|
| **iOS** | Strong BackdropFilter blur, light fill, soft highlight borders |
| **Android** | Translucent Material + stronger blur (σ≈32, fill≈0.5) |
| **macOS** | Acrylic-style title bar + sidebar (σ≈40) |
| **Windows / Linux** | Acrylic/mica-like sidebars (σ≈36) |

Applied to: app bars, bottom nav, desktop sidebar, title bar, flyouts/menus, pop-up sheets, **reader chrome only**.

## Cloud Sync (opt-in, OFF by default)

Settings → App → **Cloud Sync**.

| Provider | How to configure |
|----------|------------------|
| **WebDAV** | Directory URL + user + password. If URL already includes the folder (`…/dav/来`), set Remote Folder to `/`. |
| **Alist / OpenList** | Alist root URL (no `/dav`) + login + path (e.g. `/来`). Mount Baidu / 123 / Aliyun / Quark *inside Alist*. |
| **Quark (夸克)** | Browser Cookie from `pan.quark.cn` + folder FID. Prefer Alist mount when possible. |

## Build notes

- Android APK: `flutter build apk --release` / split ABI on Linux.
- **macOS `.app` / `.dmg`**: needs a Mac host (`flutter build macos`).
- iOS IPA: needs Mac + Xcode.

## Known limitations

- Quark upload/download depends on unofficial endpoints and may break without notice.
- Direct Baidu / 123 / Aliyun APIs stay routed through Alist.
