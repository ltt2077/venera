# Venera Glass fork — 1.7.5+175

Fork of archived [venera-app/venera](https://github.com/venera-app/venera) (last upstream v1.6.3).
GPL-3.0. No bundled comic sources.

## 1.7.5 — Secondary-page white flash fix + tunable liquid glass

User feedback on 1.7.4: bottom-tab switches were fine, but opening **History / Settings subpages** (Navigator.push) still flashed white. Also asked for **user-tunable liquid glass parameters**.

### Push / pop white flash
- Root cause: Android `PredictiveBackPageTransitionsBuilder` paints opaque `colorScheme.surface`, and `SlidePageTransitionBuilder` wrapped pages in a default `Material` fill.
- When liquid glass is ON: routes are **`opaque: false`**, PredictiveBack is skipped, slide transition uses **transparent Material**, page built with `MaterialType.transparency`.
- History scaffold uses transparent background under glass.

### 液态玻璃参数 (Appearance)
When Liquid Glass is ON, a new section exposes live knobs (persisted in `appdata.settings`):
- Quality preset: 自适应 / 高 / 标准 / 省电
- Blur · Frost · Tint opacity · Thickness · Refractive index · Specular
- Dock side margin · Dock corner radius
- Reset to defaults

Wired through `Glass.settingsFor` / `Glass.qualityFor` / floating `GlassTabBar.bottom`. `LiquidGlassWidgets.wrap` rebuilds with the chosen adaptive/fixed quality.

### 中文摘要
- 修历史／设置等**下一级页面**推入时的白闪（底栏切换本来就正常）。
- 外观 → **液态玻璃参数**：可调模糊／着色／折射／高光／底栏边距圆角／画质档，支持重置。

## Prior
- 1.7.4 — BiliPai floating liquid dock + tab flash fix
- 1.7.3 — real `liquid_glass_widgets` shaders + adaptive quality
- 1.7.2 — Cloud Sync save white screen · zh · DIY glass attempt
- 1.7.1 — Alist 404 · multi-profile smart sync
