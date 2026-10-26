# Venera Glass fork — 1.7.4+174

Fork of archived [venera-app/venera](https://github.com/venera-app/venera) (last upstream v1.6.3).
GPL-3.0. No bundled comic sources.

## 1.7.4 — BiliPai-inspired floating liquid dock + tab-switch flash fix

User feedback on 1.7.3: bottom nav still looked like a **full-width frosted strip**, and quick tab switches flashed white / briefly misaligned.

### Floating liquid-glass bottom dock
Inspired by third-party B站 client [BiliPai](https://github.com/jay3-yy/BiliPai) (Compose + Haze / AndroidLiquidGlass floating capsule).

- Replaced edge-to-edge blur strip with **`GlassTabBar.bottom`** from [`liquid_glass_widgets`](https://pub.dev/packages/liquid_glass_widgets) — floating pill with horizontal margin, soft elevation over content, jelly/spring selection indicator, refraction + specular highlight.
- Content **extends under** the dock (`Stack` overlay + stable `MediaQuery` bottom inset) so lists scroll behind the capsule.
- Dock uses `GlassQuality.premium` (track `standard` for GPU savings). `liquidGlass` OFF → solid Material floating capsule fallback.

### Tab-switch white flash / misalignment
- Replaced `AnimatedSwitcher` with **`IndexedStack`** — tabs stay alive; no fade that reveals opaque white chrome mid-transition.
- Top actions always include Search + Settings so the app bar no longer jumps when leaving Home.
- Bottom inset reserved consistently every frame (no mid-frame padding change).

### 中文摘要
- 底栏改为 BiliPai 风格**悬浮液态玻璃胶囊**（`GlassTabBar.bottom`），不再是贴边磨砂条。
- 切页白闪／短暂错位：页面保活 + 顶栏图标不再忽隐忽现。
- 关闭「液态玻璃」仍为悬浮实色胶囊底栏。

## Prior
- 1.7.3 — real `liquid_glass_widgets` shaders + adaptive quality
- 1.7.2 — Cloud Sync save white screen · zh · DIY glass attempt
- 1.7.1 — Alist 404 · multi-profile smart sync
