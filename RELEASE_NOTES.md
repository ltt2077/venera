# Venera Glass fork — 1.7.3+173

Fork of archived [venera-app/venera](https://github.com/venera-app/venera) (last upstream v1.6.3).
GPL-3.0. No bundled comic sources.

## 1.7.3 — real liquid glass (`liquid_glass_widgets`)

Prior DIY `BackdropFilter` + mesh-on-opaque-scaffold could never look like glass.
This release integrates **[`liquid_glass_widgets` ^1.15.0](https://pub.dev/packages/liquid_glass_widgets)** (iOS 26/27-style custom fragment shaders; works on Android Impeller).

### Package APIs used
- `LiquidGlassWidgets.initialize()` + `LiquidGlassWidgets.wrap(adaptiveQuality: true, brightnessResolver: Theme.maybeBrightnessOf, …)`
- `AdaptiveGlass` (chrome via our `GlassSurface` / `GlassChrome`)
- `GlassContainer.card` (Cloud Sync / settings cards via our `GlassCard`)
- `LiquidGlassSettings.ios27Light` / `ios27Dark`
- Soft aurora `GlassWallpaper` behind transparent scaffolds so refraction has content to sample

### Quality strategy (性能优先 · mid Android)
| Surface | Quality |
|---|---|
| Nav / app / side bars | `GlassQuality.premium` (adaptive may downgrade) |
| Pop-up sheets | `GlassQuality.standard` |
| Cloud Sync profile rows / list cards | `GlassQuality.minimal` (shader-free frost; keeps scroll smooth) |

`adaptiveQuality: true` benchmarks the device and degrades under thermal/GPU pressure.
`liquidGlass` setting OFF (or high-contrast / bold-text) restores solid Material.

### Also kept from 1.7.2
- Cloud Sync save white-screen fix (`popPopUp`)
- Multi-profile smart sync · Alist `/dav` fix · 中文文案

### 中文摘要
- 接入真正的开源液态玻璃包 `liquid_glass_widgets`（着色器折射，非假半透明卡片）。
- 导航栏用高级质量，列表卡片用 minimal，保证中端安卓流畅。
- 关闭「液态玻璃」开关即恢复实色 Material。

## Prior
- 1.7.2 — save white screen · zh · DIY glass attempt
- 1.7.1 — Alist 404 · multi-profile smart sync
