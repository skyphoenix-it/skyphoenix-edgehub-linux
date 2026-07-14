# EdgeHub — Roadmap

**Last updated:** 2026-07-14

EdgeHub is already a complete, shipping-quality application. This roadmap reflects
that: the foundation is **done**, and the work ahead is a focused path to a tagged
**v1.0** followed by optional post-1.0 packs. It is deliberately realistic — nothing
here is a promise dressed up as a feature.

---

## Foundations — DONE ✅

The core product exists, is tested, and runs on real hardware today.

### Application
- [x] Native Rust core (config, EDID display identity, system metrics) exposed over a stable C ABI
- [x] Qt 6/QML hub: multi-page swipe dashboard, edit mode (add/remove/move/resize tiles & pages)
- [x] Schema-driven per-widget configuration with in-widget controls
- [x] On-device Settings, first-run wizard, and Diagnostics screen
- [x] EDID-based display auto-detect; real HID auto-rotate on the Xeneon Edge
- [x] Control-socket IPC and single-instance behavior
- [x] Local TOML configuration (no account, no telemetry)

### 22 widgets
- [x] **System:** CPU, GPU (AMD Radeon), Memory, Network, Disk, Sensors
- [x] **Time & ambient:** Clock, Analog Clock, Moon Phase
- [x] **Focus & life:** Focus Timer (Pomodoro), Tasks, Right Now, Quick Note, Habit Streak, Hydration, Break Reminder
- [x] **Media:** Now Playing (MPRIS)
- [x] **Info:** Calendar (ICS), Weather (Open-Meteo), Countdown, End of Day, Daily Quote

### Design system
- [x] 22 themes, 14 accent colors, 7 animated backgrounds, static wallpapers
- [x] Glass / glow and a reduced-motion mode, shared across every widget

### Companion — EdgeHub Manager
- [x] Live WYSIWYG clone of the Edge (drag / reorder / resize)
- [x] Layout, Appearance, Images, Display, and About tabs
- [x] Themeable chrome (Dark / Light / Default)

### Quality & delivery
- [x] Rust unit suite (~96% line coverage)
- [x] C++ QtTest suite (~97% filtered line coverage)
- [x] QML behavior-matrix harness (~99% of tracked behaviors)
- [x] Runtime E2E suite + real-hardware E2E suite (`tests/hardware/edge_e2e.py`)
- [x] Live, green CI gated at ≥95% coverage
- [x] AUR package (build-tested); AppImage / Flatpak / CPack DEB/RPM recipes authored

---

## v1.0 — in development 🔄

The goal of v1.0 is to turn "a great dashboard for me" into "a dashboard anyone can
make their own in minutes," with accessibility and privacy as first-class concerns.
Approved epics:

### Preset library
- A curated set of **12–15 ready-made screens** (focus, ambient, system, media, etc.)
  users can apply and tweak, so a fresh install looks great without edit-mode work.

### Generic primitive widgets
- **HTTP/JSON** widget (poll an endpoint, map fields to a display)
- **KPI** widget (single big number + trend)
- **Command** widget (run a local command, show its output)
- **Webhook** widget (react to inbound events)

These make EdgeHub extensible without a plugin system.

### Calm / accessibility foundation
- Accessible typefaces (**Atkinson Hyperlegible**, **Lexend**)
- Color-blind-safe **Okabe–Ito** palette option
- A **Calm ↔ Energized** intensity control
- Honor the OS **reduce-motion** preference automatically

### New wellness widgets
- Medication reminder
- Brain-dump (fast capture)
- Visual timer
- Now / Next

### Trust & control
- **Encrypted secrets** for widget credentials (e.g. API tokens)
- **Egress / offline control** — per-widget network allow-listing and a global offline mode
- **Enterprise compliance pack** — packaging and documentation for managed deployments

### Release blockers
- Harden AppImage / Flatpak / DEB / RPM into published, verified artifacts
- Finalize install/upgrade/uninstall paths and release notes

### Release train
**alpha → beta → RC → GA.** Each stage tightens scope and stability; GA is the tagged
1.0 with signed artifacts and published packages.

---

## Post-1.0 packs

Optional, demand-driven additions layered on the stable 1.0 core. Not committed
timelines — direction.

### Segment integration packs
- **Streamer:** OBS / streaming controls
- **Gaming:** MangoHud telemetry
- **Ops / dev:** Prometheus, CI status
- **Home:** smart-home controls
- **Finance:** market data

### Platform
- **WASM widget SDK + marketplace** — sandboxed third-party widgets with a stable manifest and a review/distribution flow
- **Internationalization (i18n)** — multi-language UI

---

*EdgeHub is an independent product of SKYPhoenix IT and is not affiliated with Corsair.*
