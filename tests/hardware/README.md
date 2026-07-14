# Real-hardware tests (Xeneon Edge)

Headless end-to-end tests that run against the **actual Edge panel** — interaction
(synthetic touch), live IPC, performance, and stability. Complements the offscreen
`tests/ui` qmltest suite, which can't exercise the real compositor, touch input, or
the C++ backend on-device.

## Requirements

- The Edge connected and enabled (normally DP-3). The hub auto-detects it.
- A release build: `./scripts/build.sh release` (produces `build/xeneon-edge-hub`).
- `/dev/uinput` writable by your user — for synthetic touch. On this box the
  openlinkhub/Corsair daemon grants it via an ACL (`getfacl /dev/uinput` should show
  `user:<you>:rw-`). Otherwise add yourself to the `input` group.
- `python3` with `PIL` (Pillow) only if you want screenshots; the test itself needs
  no third-party packages. `kscreen-doctor` (KDE) is used to auto-detect geometry;
  override with `XENEON_EDGE_GEOM="x,y,w,h"` and `XENEON_CANVAS="w,h"` on other setups.
- No hub already running (the test launches its own and owns the control socket).

## Run

```sh
python3 tests/hardware/edge_hw_test.py     # exits 0 on pass, 1 on any failure; prints JSON
```

It **backs up and restores** `~/.config/xeneon-edge-hub/config.toml` (a live
`setUiState` persists to disk), so your layout/appearance is untouched.

## What it covers

- **Launch/placement** on the Edge + control socket comes up.
- **IPC**: `ping`, 300 `getUiState` round-trips (latency p50/p99), 25 concurrent
  connections, 500 connect/disconnect cycles — no drops.
- **Robustness**: malformed JSON, a >8 MB oversized message, and a partial message
  are all handled without crashing the hub.
- **Synthetic touch** (real events via a pure-python uinput virtual pointer): opens a
  tile's expanded overlay, taps the Focus preset segments and **verifies via
  `getUiState` that `cfg.preset` changed** (skipped if page 0 has no Focus tile),
  closes via the Done bar, swipes between pages, and runs a 40-tap storm.
- **Stability/perf**: no fd/thread leak, RSS reported, clean shutdown (exit 0).

## Files

- `uinput_touch.py` — reusable pure-python synthetic touch/pointer (no sudo, no
  ydotool). `VPointer` + `detect_edge()`. See its header for the two Wayland gotchas
  (24-byte `input_event` packing; the move→settle→click sequence).
- `edge_hw_test.py` — the consolidated test above.

## Not covered (needs a human)

- **Physical rotation → auto-rotate**: the sensor is read from `/dev/hidraw5` and the
  pipeline is wired + debounced, but only a person can physically turn the panel.
- Subjective feel (animation smoothness, readability at arm's length).

---

## `edge_e2e.py` — comprehensive E2E suite (hub + Manager)

The big one. Drives the **real hub on the Edge** and the **Manager**, covering
"everything", and reports a single pass/fail. Uses an **isolated
`XDG_CONFIG_HOME`** (keeping the real `XDG_RUNTIME_DIR` for Wayland + the control
socket), so the live config is never touched — no backup/restore needed.

```sh
python3 tests/hardware/edge_e2e.py                 # full run (~20–30 min)
E2E_SOAK_SECONDS=5 python3 tests/hardware/edge_e2e.py   # quick smoke (~2 min)
```

**Coverage (~199 checks):**
- **Widget lifecycle** — add / render / no-error / resize (1↔2) / remove for **all
  22 widget types** (via IPC `setUiState`/`getUiState` + Edge screenshots).
- **Theming** — every theme, every background style, per-widget accent override,
  glass/glow, each verified in state + grabbed.
- **Interaction (synthetic touch)** — compact widget controls (Focus Start/Pause,
  Hydration ±, Task toggle) verified over IPC; **page-swipe navigation** verified
  by distinct per-page wallpapers (average-colour distance).
- **IPC** — malformed/partial/oversized input (no crash), latency p50/p99 over 200
  round-trips, 20 concurrent connections.
- **Soak** — sustained **mixed** operations (add/remove/resize/theme/background/
  multi-page + periodic swipes) for `E2E_SOAK_SECONDS` (default 1200 → ~20 min);
  the bulk of the runtime and the real stability signal.
- **Manager** — Dark / Light / Default chrome all render with 0 QML errors.

Modules: `e2e_harness.py` (launch/IPC/touch/grab primitives), `e2e_widgets.py`,
`e2e_theming.py`, `e2e_interaction.py`, orchestrated by `edge_e2e.py`.

The Manager's **drag-reorder** logic (incl. the "name-tag stuck in air" regression)
is covered deterministically offscreen by `tests/ui/tst_edgeclone_drag.qml`.
