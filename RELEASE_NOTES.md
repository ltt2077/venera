# Venera Glass fork — 1.7.0+170

Fork of archived [venera-app/venera](https://github.com/venera-app/venera) (last upstream v1.6.3).
GPL-3.0. No bundled comic sources.

## Liquid Glass UI (default ON)

Settings → Appearance → **Liquid Glass**. Classic opaque chrome remains when toggled off.

Platform profiles (Flutter materials; no private native frameworks required):

| Platform | Approach |
|----------|----------|
| **iOS** | Strong BackdropFilter blur, light fill, soft highlight borders (Cupertino-like) |
| **Android** | Material translucent surfaces + blur, dynamic_color harmony preserved |
| **macOS** | Acrylic-style title bar + sidebar (higher blur σ≈40), window_manager compatible |
| **Windows / Linux** | Acrylic/mica-like sidebars, title bar, sheets (σ≈36) |

Applied to: app bars, bottom nav, desktop sidebar, title bar, flyouts/menus, **reader chrome only** (comic pages are never blurred).

High-contrast / bold-text accessibility modes fall back to opaque surfaces.

## Cloud Sync (opt-in, OFF by default)

Settings → App → **Cloud Sync**. Same `.venera` data bundle as classic WebDAV.

| Provider | How to configure |
|----------|------------------|
| **WebDAV** | URL + user + password + remote folder. Alist’s WebDAV endpoint works here too. |
| **Alist / OpenList** | Base URL + login + remote path (e.g. `/venera`). Mount Baidu / 123 / Aliyun / Quark *inside Alist* to sync those clouds without fragile direct APIs. |
| **Quark (夸克)** | Paste browser Cookie from `pan.quark.cn` + folder FID (`0` = root). Unofficial web API; cookies expire — prefer Alist mount when possible. |

Actions: **Test** connection, manual Upload/Download, Auto Sync toggle (mirrors previous WebDAV behavior). Credentials stay in app settings; tokens/cookies are redacted in logs.

## Build notes

- Android APK: buildable on Linux (`flutter build apk --release` / split ABI).
- **macOS `.app` / `.dmg`**: implement glass path is in tree; full binary needs a Mac host (`flutter build macos`). Linux CI cannot produce a signed macOS app.
- iOS IPA: needs Mac + Xcode; `ios/` kept analysis-friendly.

## Known limitations

- Quark upload/download depends on unofficial endpoints and may break without notice.
- Direct Baidu / 123 / Aliyun APIs are intentionally routed through Alist rather than brittle reverse-engineered clients.
- No Windows binary in this Linux build environment (code still targets desktop).
