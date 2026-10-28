# Venera Glass fork — 1.7.7+177

- Load main tabs on first visit, retain state and pause inactive tickers.
- Debounce automatic cloud sync and honor the auto-sync switch and sync mode.
- Restore cloud profiles, credentials and sync flags from manual full backups.
- Keep the original `.venera` entries; add optional metadata for auto-sync flags.
- Snapshot SQLite databases through the online backup API, including WAL data.
- Upload before pruning old backups; retain the latest backup for ten days.
- Fix numeric revision sorting, skipped equal/older downloads and smart-sync conflicts.
- Add backup, retention, database and tab regression checks.

See [backup compatibility audit](doc/backup_compatibility.md) for coverage and
validation limits. Core checks, Flutter tests and changed-library analysis passed on the first
implementation commit; final CI rerun pending. Device/package checks remain unverified.

# Venera Glass fork — 1.7.6+176

Fork of archived [venera-app/venera](https://github.com/venera-app/venera) (last upstream v1.6.3).
GPL-3.0. No bundled comic sources.

## 1.7.6 — Fix secondary-page overlap / old-page residue

Critical regression from 1.7.5: opening **History / comic details** showed the home list, tags, and bottom nav bleeding through under the new page (stacked UI).

### Root cause
`AppPageRoute.opaque = false` + transparent Material (added to kill white flash) left the previous route in the paint tree. Flutter kept drawing MainPage underneath translucent scaffolds.

### Fix (opaque routes again — no see-through pages)
- **`AppPageRoute.opaque` restored to `true`** — previous route is fully covered.
- Pushed pages wrap in **theme `ColorScheme.surface` Material** (not `Colors.white`, not fully transparent) so transitions stay on-theme without a white flash.
- `SlidePageTransitionBuilder` uses the same opaque surface fill; PredictiveBack stays off when liquid glass is on.
- History / comic-detail scaffolds use solid theme surface; **glass chrome** (app bars, floating BiliPai dock, cards, knobs) stays translucent *on top* of the opaque page root.
- Wallpaper remains under MainPage only — not visible through pushed routes.

### Kept from 1.7.5
- Tunable 液态玻璃参数 · floating BiliPai dock · IndexedStack tabs · cloud sync / zh

### 中文摘要
- 修「点进历史／详情后旧页面残留重叠」：路由改回不透明，用主题色实底盖住下层。
- 白闪用主题色实底滑动过渡压掉，不再靠透明路由。
- 液态玻璃参数、悬浮底栏、云同步等保留。

## Prior
- 1.7.5 — Secondary-page white flash + tunable liquid glass
- 1.7.4 — BiliPai floating liquid dock + tab flash fix
- 1.7.3 — real `liquid_glass_widgets` shaders + adaptive quality
- 1.7.2 — Cloud Sync save white screen · zh · DIY glass attempt
- 1.7.1 — Alist 404 · multi-profile smart sync
