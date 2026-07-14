# EdgeHub

**Turn your Corsair Xeneon Edge — or any secondary/portrait touchscreen — into a beautiful, native Linux dashboard.**

EdgeHub by [SKYPhoenix IT](https://skyphoenix-it.com) is a widget dashboard built for portrait touchscreens. No browser, no Electron, no web server, no account, no telemetry — a Rust core, a Qt 6/QML front-end, and a companion desktop app that lets you design your screen from your PC.

[![CI](https://github.com/skyphoenix-it/XeneonEdge_Linux/actions/workflows/ci.yml/badge.svg)](https://github.com/skyphoenix-it/XeneonEdge_Linux/actions/workflows/ci.yml)
[![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg)](#license)

![EdgeHub dashboard with animated orbs background](docs/marketing-site/assets/edge-dashboard-orbs.png)

---

## What it is

The Corsair Xeneon Edge is a 2560×720 portrait secondary touchscreen. EdgeHub gives it (and other secondary or portrait displays) a purpose-built home screen: multiple swipeable pages of live widgets — system metrics, a Pomodoro timer, now-playing controls, weather, your calendar — that you arrange by touch, right on the device.

- **Native and light.** A Rust core does the metrics and config work; Qt 6/QML draws the UI. No Chromium, no bundled runtime.
- **Designed for touch.** Large targets, swipe between pages, in-widget controls, and on-device settings — you never need a keyboard to use it.
- **It finds the right screen.** EDID-based display detection puts EdgeHub on your Edge (or chosen display), and real HID auto-rotate follows the panel when you flip it.
- **Design it from your desk.** The companion **EdgeHub Manager** is a live, WYSIWYG clone of your Edge — drag, reorder, resize, and restyle from your main monitor.

---

## Features

### 22 widgets

| Category | Widgets |
|----------|---------|
| **System** | CPU load & temp, GPU (AMD Radeon utilization & temp), Memory, Network throughput, Disk usage, combined Sensors |
| **Time & ambient** | Clock, Analog Clock, Moon Phase |
| **Focus & life** | Focus Timer (Pomodoro), Tasks, Right Now, Quick Note, Habit Streak, Hydration, Break Reminder |
| **Media** | Now Playing (MPRIS — Spotify, browsers, any player) |
| **Info** | Calendar (subscribe via ICS URL), Weather (Open-Meteo), Countdown, End of Day, Daily Quote |

System metrics come straight from the Rust core / the kernel. Focus, task, note, habit and hydration widgets persist your data locally. Calendar and Weather only reach the network for the feeds you configure.

### Make it yours

- **22 themes** (from clean dark/light and high-contrast/OLED to Nord, Dracula, Gruvbox, Catppuccin, Tokyo Night, Synthwave and more), **14 accent colors**, **7 animated backgrounds** (orbs, mesh gradient, aurora, waves, starfield, bokeh, grid) plus static wallpapers.
- **Glass, glow, and a reduced-motion mode** — a single shared design system keeps every widget consistent.
- **Edit mode** to add, remove, move, and resize tiles across multiple pages, with schema-driven per-widget configuration and in-widget controls.
- **First-run wizard**, on-device **Settings**, and a **Diagnostics** screen.

![EdgeHub with the aurora background](docs/marketing-site/assets/edge-dashboard-aurora.png)

### EdgeHub Manager (companion app)

A themeable desktop app (Dark / Light / Default chrome) that mirrors your Edge in real time:

- **Layout** — drag, reorder, and resize tiles on a live clone.
- **Appearance** — themes, accents, backgrounds, glass/glow.
- **Images** — wallpapers and per-widget imagery.
- **Display** — pick and orient the target screen.
- **About** — version and project info.

---

## Performance & privacy

- **~3.5% CPU** worst-case with every animation running; **~0.5%** with reduced motion.
- **~378 MB** RSS steady-state.
- **No telemetry. No account. Local-only configuration** (plain TOML on your machine). EdgeHub only touches the network for widgets you explicitly configure — e.g. Weather (Open-Meteo) or a Calendar (ICS) feed.

---

## Install

> EdgeHub is a complete, shipping-quality application. Packaging is being hardened toward a tagged **v1.0** (see the [roadmap](#roadmap)).

### Arch / CachyOS (AUR)

```bash
yay -S xeneon-edge-hub
```

### AppImage / Flatpak / .deb / .rpm

AppImage and Flatpak recipes and CPack `.deb` / `.rpm` / portable-tarball generation are authored in this repo and being finalized for v1.0. Until the hosted artifacts land, build from source below. See [`packaging/README.md`](packaging/README.md) for the current state of each format.

---

## Build from source

### Prerequisites

- **Rust** 1.75+ (stable)
- **C++17 compiler** (GCC 12+ or Clang 16+)
- **CMake** 3.22+
- **Qt 6.5+** with development headers (QtQuick, QtWayland, QtDBus, QtSvg)

**Arch / CachyOS**

```bash
sudo pacman -S rust cmake gcc qt6-base qt6-declarative qt6-wayland qt6-tools
```

**Ubuntu 24.04 LTS**

```bash
sudo apt install cargo cmake g++ qt6-base-dev qt6-declarative-dev \
  qt6-wayland-dev qt6-tools-dev libglib2.0-dev
```

### Build & run

```bash
git clone https://github.com/skyphoenix-it/XeneonEdge_Linux.git
cd XeneonEdge_Linux
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

./build/app/xeneon-edge-hub          # the on-device hub
./build/manager/xeneon-edge-manager  # the companion Manager
```

### Test

```bash
cargo test                     # Rust core
cmake --build build --target test
./scripts/run_all_tests.sh     # Rust + QML behavior matrix + ctest
```

---

## Architecture

```
Rust core (config · EDID · metrics · FFI)  ──C ABI──▶  Qt 6 / QML (hub + Manager)
                                                         │
                    local TOML config ◀── control-socket IPC · single-instance
```

- **Rust core** owns configuration, EDID display identity, system metrics, and exposes a stable C ABI.
- **Qt 6/QML** renders the hub and the Manager on top of that core.
- The hub and Manager talk over a **control socket**; the app is **single-instance**.

## Quality

- **Rust:** ~110 unit tests, ~96% line coverage (`cargo llvm-cov`).
- **C++:** QtTest suite, ~97% filtered line coverage.
- **QML:** a behavior-matrix harness (~99% of tracked behaviors).
- **End-to-end:** a runtime E2E suite plus a real-hardware suite (`tests/hardware/edge_e2e.py`).
- **CI is live and green,** gated at ≥95% coverage.

---

## Roadmap

EdgeHub's foundations — the 22 widgets, the Manager, the theme system, the test suite, live CI, and AUR packaging — are **done and shipping-quality**. Work now targets a tagged **v1.0**: a curated preset library, generic primitive widgets (HTTP/JSON, KPI, command, webhook), and a calm/accessibility foundation (accessible fonts, an Okabe–Ito-safe palette, honoring OS reduce-motion). See **[ROADMAP.md](ROADMAP.md)** for the full plan and the alpha → beta → RC → GA train.

There is also a marketing overview at [`docs/marketing-site/index.html`](docs/marketing-site/index.html).

---

## License

Dual-licensed under either of:

- **MIT License** ([LICENSE-MIT](LICENSE-MIT) · <http://opensource.org/licenses/MIT>)
- **Apache License 2.0** ([LICENSE-APACHE](LICENSE-APACHE) · <http://www.apache.org/licenses/LICENSE-2.0>)

at your option.

**Qt note:** EdgeHub links against Qt 6 (LGPLv3). Dynamic linking against system Qt satisfies LGPL; static linking carries the usual re-linking obligations.

App-id: `com.skyphoenix_it.XeneonEdgeHub` · Companion: `com.skyphoenix_it.XeneonEdgeManager`

## Security

See [SECURITY.md](SECURITY.md) for the security policy and how to report a vulnerability.

---

## Not affiliated with Corsair

EdgeHub is an independent product of SKYPhoenix IT. It is **not affiliated with, sponsored by, or endorsed by Corsair.** "Corsair" and "Xeneon Edge" are used only to describe hardware compatibility.

*EdgeHub — your secondary screen, at its best.*
