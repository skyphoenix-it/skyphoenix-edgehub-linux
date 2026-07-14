# Session handoff — continue from here

_Last updated: 2026-07-14 (Manager UI/UX + robustness + overnight autonomous session). On
`master`; PR #1 (`552729c`) plus follow-up direct-to-master commits, CI green._

## Current state: GREEN — 95%+ coverage across all layers

Full plan + results: `docs/DEV_AND_TEST_PLAN.md`, `docs/MANAGER_UIUX_PLAN.md`. Run
everything: `./scripts/run_all_tests.sh` (→ `RESULT: SUCCESS`); coverage: `./scripts/coverage.sh`.

- **Build**: `./scripts/build.sh release` — clean (hub + manager).
- **QML**: `./scripts/run_ui_tests.sh` — ALL UI TESTS PASSED. Behavior matrix
  `python3 scripts/qml_coverage.py` — **100%** (165/165).
- **Rust**: `cd core && cargo test` — **116 passed**; **97.4%** line (config.rs 98.3%).
- **C++**: `./scripts/run_cpp_tests.sh` — **15/15 ctest**; ~97% filtered line.
- **Runtime E2E**: `tests/runtime/run_focus_goal_bonus.sh` — drives the real hub
  binary headless (offscreen) and asserts on the state it persists to `config.toml`;
  proves the Focus daily-goal bonus fires exactly once. Wired into
  `run_all_tests.sh` as suite #5 (SKIPs if no hub binary is built/installed; pin
  one with `XENEON_HUB=…`). See `tests/runtime/README.md` for the config-schema /
  SIGKILL / `pkill` gotchas.

### Install the latest build
Package staged at **`~/xeneon-edge-hub-0.1.0.r61-1-x86_64.pkg.tar.zst`** (version
`v0.1.0-32-gaf048c7`, shown in the Manager nav + hub Diagnostics) — **installed**
this session (was r39). Rebuild/reinstall in your terminal (closes stray instances
first): `pkill -f xeneon-edge; sudo pacman -U
~/xeneon-edge-hub-0.1.0.r61-1-x86_64.pkg.tar.zst`.

### Overnight autonomous pass — real bugs fixed (adversarial reviews)
- **habit streak cap** (`7064c57`): streak was capped at 28 (heatmap-window prune);
  now a persisted number, milestones ≥30 fire, backward-compatible.
- **EOD overnight window** (`4e9265e`): night-shift (22→06) was wrong after midnight;
  now selects the day-earlier window candidate.
- **sensors 0% fabrication** (`40c4d93`): CPU/RAM no longer show a fake 0% before the
  first metrics frame (S4).
- **offline-edit loss** (`1f90515`, P1 data loss): a connected edit didn't update the
  reconcile baseline, so an offline edit after a hub restart could be dropped — fixed +
  regression test.
- **store hardening** (`8001ffc`): clamp tile w/h to [1,2], prototype-safe page-name
  dedup (`valueOf`/`toString`/… no longer spuriously renamed), no redundant flash-write
  from ensureSettings after applyExternal.

### Post-PR#1 work (newest first)
- **Manager UI/UX + themes + robustness** (`8df1ccc`/`fafb133` + follow-ups): dark
  `QPalette` on both apps (config Switch/Slider/Button/ScrollBar/dialog buttons no
  longer render as pale Fusion), restyled config controls, **config live-preview now
  scales to fit** (no clipped action rows), hover/cursor affordances. **Themes 8→22** (this batch 8→16;
  synthwave/cyberpunk/deep_forest/deep_ocean/ember/vaporwave/rose_gold/matrix; then +6 nord/dracula/solarized/gruvbox/catppuccin/tokyonight → 22),
  **accents 8→14**. `_normaliseDoc` is now a **validator** (corrupt/hostile pages/tiles/
  tasks can't blank the dashboard). IPC RX-cap, 25 MB image guard, saveError signal.
- **Single-instance guard** (`53e9dfa`): `app/src/single_instance.h` (QLockFile) on
  both apps — a 2nd hub/manager exits instead of racing config.toml (skipped when
  `XENEON_GRAB` set so QA grabs still work). This is the fix for the multi-writer
  config churn seen with several instances up at once.
- **Config self-binding fix** (`a11e24b`): `WidgetConfigPanel` property renamed
  `store`→`st` — `store: store` at the call sites self-bound to null, so the ENTIRE
  config form (hub + Manager) showed defaults + dropped edits. Regression gate
  `tst_config_panel_wiring.qml`.
- **Version in UI** (`0fb8ceb`): git-describe → `XENEON_VERSION` → `appVersion()` →
  Manager nav + hub Diagnostics. PKGBUILD passes `-DXENEON_VERSION_OVERRIDE`.
- New tests: `tst_config_panel_wiring`, `tst_all_widget_configs` (all 23 types render),
  `tst_store_validation`, `tst_single_instance` (C++), `tst_rx_cap` (C++).

### Known follow-up (not yet fixed — needs a design decision)
- **Manager `setTargetDisplay`/`setAutostart` write config.toml directly even when the
  hub is connected** (two-writer race): the hub's in-memory config still holds the old
  target/autostart, so the hub's next save reverts the Manager's change. `saveUiState`
  already avoids this (IPC-only when connected), but display/startup have no IPC path —
  fixing it needs a new hub control-socket command (e.g. `reloadConfig` or per-field
  setters) so the hub adopts the change. Narrow window (these are set rarely) but real.
  The single-instance guard + IPC-only ui_state cover the common churn; this is the
  remaining edge. `manager/src/manager_backend.h:setTargetDisplay/setAutostart`.

### Resolved: FocusWidget goal bonus now fires once
- **FocusWidget goal bonus/celebration is now ONE-TIME.** Previously it re-fired every
  session past the daily goal (`done >= dailyGoal`). Changed to `done === dailyGoal` in
  `FocusWidget.advance()`, so the +50 bonus + "🎯 Goal reached!" fire only on the session
  that crosses the goal; later sessions get the ordinary +10. Regression gates:
  `tst_gen_focus.qml::test_reaching_goal_awards_bonus` (crossing → +60) and
  `test_goal_bonus_does_not_refire_when_exceeding` (past goal → +10, no re-celebration);
  `tst_focus.qml::test_reward_points_and_goal_bonus` still green.

### Prior test-push (PR #1)
- **On-device**: hub dashboard, Manager, and an expanded widget config all verified
  via `XENEON_GRAB` captures on the real Edge (DP-3). Wallpaper with spaces + `#`
  in the path loads correctly through `configBridge.imageUrl()`.

## What the last few commits did (newest first)

- **`736ba9f` — stop rewriting config.toml every 2s.** Metric widgets (cpu/gpu/ram/net)
  mirror sparkline history (`hist`/`peakRx`/`peakTx`) into the store every sample; the
  store used to persist every write → the hub rewrote `config.toml` ~every 2s forever
  (flash wear + a two-writer atomic-rename race with the Manager: "Failed to save
  config: No such file or directory"). Those keys are now **ephemeral** in
  `DashboardStore.qml` (`_ephemeralKeys`): kept in memory for compact↔expanded sparkline
  sharing, but a volatile-only write bumps `revision` without scheduling a save, and
  `_persistableData()` strips them from disk. Idle saves: ~1/2s → 0. 2 new regression
  tests in `tst_store_tiles.qml`.
- **`7cd491e` — shell/manager bug sweep + cross-file wiring.** Integrated the 8-agent
  QML fixes (Manager S2/S11/imageUrl/syncTheme guard/tall-tile clone/dialog/wizard; hub
  Dashboard S7/gridCols/expand/overlay-close, SettingsPanel S2, Diagnostics scroll+labels,
  main.qml keyboard-lift+diagnostics bindings). Plus the cross-file bits the agents could
  not do: `ConfigBridge::imageUrl()` on the **hub** (hub exposes `configBridge`, NOT the
  Manager's `backend`), S9 screen-hotplug rebuild+push of `screensData`, S7 accent on
  `WidgetChrome`'s BackdropLayer.
- **`ee63764`** — the big Phase 0–3 widget/shared-infra/Rust/C++ bug fixes.
- **`a5a742a`** — generated regression suites + `docs/BUG_FIX_PLAN.md` (the master plan).

## Remaining work (prioritized)

The three former items are now **DONE** this session:
1. ~~**S10 — write-only FFI config keys**~~ ✅ Added `xeneon_config_get_reconnect` +
   `get_notify_disconnect` to `ffi.rs`/`xeneon_core.h`, exposed all three via `ConfigBridge`
   (`reconnectOnHotplug`/`notifyOnDisconnect`/`fallbackBehavior`), and wired the hub
   `screenAdded`/`screenRemoved` handlers to honor them (reconnect→re-match+migrate window;
   notify→disconnect notice; fallback=="hide"→blank). Gated by `tst_config_bridge`.
2. ~~**Two-writer atomic-save race**~~ ✅ Single-writer: when the hub is connected the Manager
   pushes `setUiState` over IPC only and does NOT write `config.toml`; it writes directly only
   when offline. Gated by `tst_manager_backend_sync` (+ the #7 edit-loss fix).
3. ~~**Duplicate "Page 5" pages**~~ ✅ `_normaliseDoc` now de-dupes `pages[].name` on
   `load`/`applyExternal` (appends " 2", " 3", …). Gated by `tst_store_dedup`.

Still open (documented, non-blocking): `mpris_bridge.cpp` D-Bus fan-out uncovered (needs a
session bus; the review confirmed the rest of the C++/core is solid). (config.rs was raised
to 98.3% this session.)

### CI is now live (first real run this session)
The trigger was fixed (`main`→`[main, master]`), so CI ran for the first time and surfaced
five environment/latent issues, all fixed in PR #1: Qt ≥6.5 via `jurplel/install-qt-action`
(apt Qt 6.4.2 lacks `MultiEffect`/`QtQml.WorkerScript`); a JS reserved-word (`float`) var
Qt 6.7 rejects; a font-metric test made deterministic (assert bounded box, not glyph ink) +
fonts installed; a **real widget bug** — `CountdownWidget` used `Layout.maximumWidth` which
Qt 6.7 ignores for oversized text, so a 5-digit day count could overflow (fixed with
`Layout.preferredWidth`); and `pipx gcovr` so CI honors the `GCOVR_EXCL` hardware-exclusion
markers (apt gcovr didn't → understated C++ coverage → merged 94.10%). CI runs Qt 6.7.3 via
aqt (older than the dev box's 6.11) on purpose — it catches exactly this class of bug.

## Key context for continuing

- **The plan**: `docs/BUG_FIX_PLAN.md` (systemic S1–S12 + discrete findings, phased).
- **Manager plan**: `.claude/plans/crystalline-mixing-hopper.md` (detailed Manager findings
  A1–A21 / B1–B18 / C P1–P3). Most are done; cross-check before re-doing.
- **CRITICAL runtime distinction**: the **hub** process exposes `configBridge` (no
  `backend`); the **Manager** process exposes `backend` (`ManagerBackend`, has `imageUrl`,
  `screensJson`, autostart, IPC). QML shared by both must feature-detect.
- **Config sync (already implemented, `manager/src/main.cpp`)**: pushLive buffers +
  flushes on `connected`, 2s reconnect timer, getUiState pull heartbeat with reconnect
  conflict-resolution (`m_pendingPushAwaitingHub`), `QFileSystemWatcher` on config.toml,
  `screensChanged` NOTIFY.
- **On-device capture**: `DISPLAY=:0 XENEON_GRAB=/path/out.png XENEON_GRAB_W=720
  XENEON_GRAB_H=2560 ./build/xeneon-edge-hub --windowed` (renders one frame → PNG → quits).
  `XENEON_EXPAND=<type>` auto-opens that widget's expanded config. Manager: same
  `XENEON_GRAB` env. Test against a temp `XDG_CONFIG_HOME` to avoid touching the live config.
- **Synthetic touch / hardware E2E**: `tests/hardware/edge_hw_test.py` (+ `uinput_touch.py`).
- Auto-memory (persists across sessions): `dashboard-architecture`, `product-decisions`,
  `companion-and-testing`, `packaging`, `ci-setup`, `runtime-e2e-testing` — read the
  index at `~/.claude/projects/-home-simon-IdeaProjects-XeneonEdge-Linux/memory/MEMORY.md`.
  A version-controlled MIRROR lives at `docs/agent-memory/` (source of truth is the
  `~/.claude/…/memory/` dir). Re-sync after any memory change, then commit:
  `cp ~/.claude/projects/-home-simon-IdeaProjects-XeneonEdge-Linux/memory/*.md docs/agent-memory/`
