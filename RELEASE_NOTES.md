# Venera Glass fork — 1.7.2+172

Fork of archived [venera-app/venera](https://github.com/venera-app/venera) (last upstream v1.6.3).
GPL-3.0. No bundled comic sources.

## 1.7.2 fixes (white screen · real Android glass · 中文 · contrast)

### 保存配置白屏 / Save profile white screen (CRITICAL)
- Root cause: profile editor called `context.pop()` on the **nested** Navigator inside `PopUpWidget`, which either threw or popped the only page → blank sheet and the parent never received the saved profile.
- Fix: `popPopUp()` always pops the root `PopUpWidget` route; Save / Back / Save & Sync all use it. Persist wrapped in try/catch; `saveData(false)` while editing so auto-upload cannot race the UI.

### Android 液态玻璃 / Real frosted glass
- Opacity tweaks alone were not enough — Cloud Sync used opaque `Card`s and the sheet had little to blur.
- `GlassSurface` now paints a frosted **gradient mesh** under a strong BackdropFilter (σ≈48 on Android) plus specular fill gradient, so frost is visible even on Impeller.
- Cloud Sync profile tiles / tips use `GlassCard`; pop-up barrier lightened; nested routes stay opaque to avoid blank glass holes.
- Theme-aware fills (`surfaceContainerLowest` / `High`) so light mode is not dark-chrome-on-light-cards.

### 中文 / Localization
- All Cloud Sync strings (云同步、配置文件、添加配置、同步模式、智能、手动、自动故障转移、保存并同步、使用中…) added to `zh_CN` / `zh_TW`.

### 中文摘要
- 修复「添加同步配置 → 保存」白屏无法保存。
- Android 真正可见的磨砂液态玻璃（模糊 + 渐变网格），云同步页卡片也走玻璃。
- 云同步界面全文中文化；明暗对比与主题一致。

## Prior: 1.7.1
Android glass opacity, Alist `/dav` 404, multi-profile smart sync.

## Liquid Glass UI (default ON)
Toggle: Settings → Appearance → Liquid Glass.
