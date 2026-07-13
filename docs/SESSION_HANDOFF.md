# Session handoff — continue from here

_Last updated: 2026-07-13. Branch: `master` (pushed to `origin/master`)._

## Current state: GREEN

- **Build**: `./scripts/build.sh release` — clean (hub + manager).
- **QML tests**: `./scripts/run_ui_tests.sh` — ALL UI TESTS PASSED.
- **Rust tests**: `cd core && cargo test` — 63 passed, 0 failed.
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

1. **S10 — write-only FFI config keys** (low priority, deferrable). `reconnect`,
   `notify_disconnect`, `fallback_behavior` are written (wizard/settings) but never read
   back into hub behavior. FFI getters exist in `core/src/ffi.rs`; the hub QML doesn't
   consume them. These govern what the hub does when the Edge display disconnects
   (auto-reopen / toast). Niche — accent/reduce-motion already persist via
   `ui_state.appearance`, so the visible settings work.
2. **Two-writer atomic-save race** — now *rare* (saves only on startup/shutdown/real edits)
   rather than every 2s, so no failures observed. A full fix would make config a single
   writer (hub owns the file; Manager mutates only via IPC). Not urgent.
3. Optional: prune the pre-existing duplicate "Page 5" pages in the live config (the
   Manager now rejects NEW empty/dup names, but old dupes persist in `config.toml`).

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
  `companion-and-testing`, `packaging` — read the index at
  `~/.claude/projects/-home-simon-IdeaProjects-XeneonEdge-Linux/memory/MEMORY.md`.
