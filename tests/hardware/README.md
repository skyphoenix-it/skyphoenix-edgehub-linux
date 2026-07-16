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
- For `edge_hw_test.py`: no hub already running (that older script still uses
  the real config + runtime dir). `edge_e2e.py` isolates both, so a live hub is
  no longer stranded or required to be stopped — but both hubs will fight over
  the Edge panel visually, so stopping the live one is still *recommended* for
  clean grabs.

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
`XDG_CONFIG_HOME`** *and* an **isolated `XDG_RUNTIME_DIR`** per spawned hub, so
the live config, the single-instance lock and the control socket of a running
hub are never touched — no backup/restore needed, and the suite can no longer
strand a live hub's Manager connection.

### How the runtime-dir isolation works (and why)

The hub binds `$XDG_RUNTIME_DIR/xeneon-edge-hub-ctl`
(`app/src/control_socket_path.h`). The harness used to keep the REAL
`XDG_RUNTIME_DIR` because Wayland's compositor socket lives there — which
meant the spawned hub bound the REAL control socket, and the harness cleanup
`os.remove()`d it, silently stranding any live hub (it keeps its listening fd,
so it *looks* healthy while the Manager can never reach it again).

`e2e_harness.E2E` now gives every spawned hub:

- a private, short (`sockaddr_un` ≈107-byte cap), 0700 `XDG_RUNTIME_DIR`
  (`self.run_dir`), where its control socket (`self.sock`) and lock land;
- `WAYLAND_DISPLAY` rewritten to an **absolute path** into the real runtime
  dir — Wayland resolves an absolute `WAYLAND_DISPLAY` without consulting
  `XDG_RUNTIME_DIR`, so the hub still reaches the compositor and renders on
  the Edge. Verified on the real session: absolute path → renders
  (grab-confirmed) with its socket in the isolated dir; relative name under
  the same isolation → cannot connect to the compositor;
- a **removal guard**: cleanup refuses to delete any socket outside its own
  private runtime dir, so no code path can unlink a live hub's socket;
- `cleanup()` (stop + remove the private dir) — `edge_e2e.py` calls it.

There is no module-level `SOCK` any more, on purpose: anything still
importing it operated on the live hub's socket and should break loudly.
Use `h.sock`. (`edge_hw_test.py`, the older standalone script, still runs
against the real config/runtime dir with its own backup/restore — don't run
it against a session with a hub you care about; `edge_e2e.py` is the safe,
current suite.)

```sh
python3 tests/hardware/edge_e2e.py                 # full run (~20–30 min)
E2E_SOAK_SECONDS=5 python3 tests/hardware/edge_e2e.py   # quick smoke (~2 min)
```

**Coverage (~199 checks):**
- **Widget lifecycle** — add / render / no-error / resize (1↔2) / remove for **every
  type in `WidgetCatalog.qml`** (30 today) via IPC `setUiState`/`getUiState` + Edge
  screenshots. The list is asserted against the catalog first, so a new widget can't
  go silently unexercised. `httpjson` is seeded with **no URL** (the shipping preset
  state, and it keeps the run offline); `kpi` uses its **local-file** source.
- **Theming** — every theme (29: 21 classics + 7 distro palettes + default dark),
  every background style (11, incl. the arch/fedora/aubergine character styles),
  per-widget accent override, glass/glow, each verified in state + grabbed. The
  `THEMES`/`BG_STYLES` lists are drift-checked against `ui/qml/Theme.qml` and
  `ui/qml/BackgroundCatalog.qml` first (same contract as the widget list), and the
  soak rotation reuses them, so a new theme or style can't go silently unexercised.
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
