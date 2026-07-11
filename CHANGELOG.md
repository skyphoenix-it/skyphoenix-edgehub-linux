# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added (Widget Experience Overhaul)
- Shared design-system foundation for a uniform, professional look across all widgets:
  - `WidgetChrome.qml`: glass card with accent glow, category-tinted wash, and consistent header (icon + title + status)
  - `PillButton.qml`, `SegmentedControl.qml`, `RingProgress.qml`: reusable, touch-friendly controls
- Expanded theme in `main.qml`: 8 selectable accent presets, category colors, glass/transparency token, widget glow toggle, secondary surfaces, and gradient partners
- `SettingsPanel.qml`: in-app appearance panel to change theme, accent color, glass/transparency, glow, and reduced motion — applied live
- Full-featured, ADHD-friendly `FocusTimer.qml`: work/short/long phases with automatic cycling, Classic/Deep/Sprint/Custom presets, session tracking, big progress ring, Start/Pause/Reset, +5 min, Skip, rotating focus nudges, and completion flash
- New widgets across categories: Hydration (Focus), Weather (Info), Now Playing (Entertainment), Doodle Pad (Entertainment), FPS/GPU (Gaming), Next Race (Gaming)
- Rebuilt all existing widgets (Clock, CPU, Memory, Sensors, Network, Tasks, Habit Streak, Moon Phase, Daily Quote, Countdown, End of Day, Dice Roller, Analog) on the shared chrome with richer visuals and interactions
- Dashboard reorganized into 5 category pages (System · Focus · Info · Play · Ambient) with a labelled, animated page indicator and gradient background
- `ExpandedWidget.qml`: category-tinted backdrop and icon + accent underline in the title

### Added (Phase 1 — Application Shell)
- Rust core library (`xeneon-core`) with:
  - Configuration management (TOML, XDG paths, versioned schema, atomic saves)
  - Display utilities (EDID parsing, hash computation, Xeneon Edge detection)
  - System metrics collection (CPU usage/temp, RAM, core count from /proc and /sys)
  - Structured logging via `tracing` with env-filter support
  - C-compatible FFI layer (30 exported functions) for Qt C++ bridge
  - 15 unit tests, all passing; clippy clean; rustfmt compliant
- C FFI header (`core/xeneon_core.h`) for C++ integration
- C++ application entry point (`app/src/main.cpp`):
  - QGuiApplication setup with CLI flags (--reset, --safe-mode, --reset-wizard)
  - QML context property injection for config, metrics, and display data
  - Real-time metrics update timer (2s interval)
  - Screen hotplug event monitoring
- QML user interface (`ui/qml/`):
  - `main.qml`: Application window with dark/light/OLED/high-contrast theme support
  - `FirstRunWizard.qml`: 4-step onboarding wizard (welcome, display select, layout choice, options)
  - `Dashboard.qml`: Clock, CPU, RAM, Focus Timer widgets with live metrics display
  - QML resource file (`qml.qrc`) for bundled Qt resources
- CMake build system (`CMakeLists.txt`):
  - Rust library integration via cargo build command
  - Qt6 QML resource compilation
  - Install targets for binary and desktop entry
- Build script (`scripts/build.sh`) with dependency checks
- Desktop entry file (`assets/xeneon-edge-hub.desktop`)
- Updated CI pipeline (GitHub Actions) with separate Rust and C++ build stages
- Comprehensive Phase 1 roadmap updates

### Added (Phase 0 — Discovery)
- Initial project structure and documentation
- Product vision document
- User personas (6 personas covering key user types)
- Use cases (15 use cases spanning all major workflows)
- MVP scope definition
- Architecture Decision Records:
  - ADR-0001: Application stack selection (Rust + Qt 6/QML)
  - ADR-0002: Widget runtime architecture (Hybrid QML + WASM)
- Architecture overview document
- Threat model and security analysis
- Widget permissions model
- Test strategy document
- Wireframe descriptions (portrait and landscape)
- Repository meta-documents (README, LICENSE, SECURITY, CONTRIBUTING, CODE_OF_CONDUCT)
- Project roadmap with 7 development phases
- Full repository directory structure

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 0.1.0 | TBD | Initial public MVP release |
| 0.0.0 | 2026-07-11 | Project inception — Phase 0 Discovery |
