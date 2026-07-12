# Xeneon Edge Linux Hub

**A native Linux widget platform for the Corsair Xeneon Edge and similar secondary touchscreen displays.**

[![CI](https://github.com/your-org/xeneon-edge-linux-hub/actions/workflows/ci.yml/badge.svg)](https://github.com/your-org/xeneon-edge-linux-hub/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

---

> **⚠️ Status: Phase 1 — Application Shell**  
> Rust core library is complete and tested. C++/Qt6 application shell in progress.  
> First public release is several months away. See [ROADMAP.md](ROADMAP.md) for development progress.

---

## What Is This?

Xeneon Edge Linux Hub turns your Corsair Xeneon Edge (or similar secondary touchscreen) into a dedicated dashboard surface. It runs as a **native Linux application** — no browser, no web server, no Electron, no Chromium.

### Features (Planned)

- **Native performance:** <1% CPU and <150MB RAM at idle
- **Multi-monitor aware:** Always opens on your chosen display, never the wrong one
- **Touch-optimized:** Purpose-built for touchscreen interaction with large touch targets
- **Portrait & landscape:** Purpose-designed layouts for both orientations
- **Widgets for everything:**
  - 🕐 Clock, date, system metrics (CPU, RAM, temps, network)
  - ⏱️ Focus timer, goals, priorities, task checklist
  - 🎵 Media controls (MPRIS: Spotify, browsers, VLC, etc.)
  - 🚀 Application launcher
  - 🎮 Gaming telemetry (GPU temps, FPS, latency — post-MVP)
- **Themable:** Dark, light, OLED black, high contrast
- **Extensible:** Community widget SDK planned (post-MVP)
- **Cross-distro:** CachyOS, Ubuntu, Arch, Fedora, and more

### Screenshots

*Coming soon — we're still building!*

---

## Quick Start (For Developers)

### Prerequisites

- **Rust** 1.75+ (stable)
- **C++17 compiler** (GCC 12+ or Clang 16+)
- **CMake** 3.22+
- **Qt 6.5+** with development headers (QtQuick, QtWayland, QtDBus, QtSvg)

#### CachyOS / Arch Linux

```bash
sudo pacman -S rust cmake gcc qt6-base qt6-declarative qt6-wayland qt6-tools
```

#### Ubuntu 24.04 LTS

```bash
sudo apt install cargo cmake g++ qt6-base-dev qt6-declarative-dev \
  qt6-wayland-dev qt6-tools-dev libglib2.0-dev
```

### Build

```bash
git clone https://github.com/your-org/xeneon-edge-linux-hub.git
cd xeneon-edge-linux-hub
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

### Run

```bash
./build/app/xeneon-edge-hub
```

### Test

```bash
cargo test
cmake --build build --target test
```

---

## Installation (End Users)

### CachyOS / Arch Linux

```bash
# From AUR (once available)
yay -S xeneon-edge-hub

# Or from release package
sudo pacman -U xeneon-edge-hub-0.1.0-1-x86_64.pkg.tar.zst
```

### Ubuntu 24.04 LTS

```bash
# From release .deb
sudo apt install ./xeneon-edge-hub_0.1.0_amd64.deb
```

### Flatpak (planned)

```bash
flatpak install flathub com.corsair.xeneonedgehub
```

---

## Documentation

| Document | Description |
|----------|-------------|
| **[Creating a Widget](docs/widgets/authoring.md)** | **Build your own widget in ~20 min (`./scripts/new-widget.sh` scaffolds it)** |
| **[Distribution & Monetizing](docs/DISTRIBUTION.md)** | **Packaging, install, licensing, and making money** |
| [Product Vision](docs/product/product-vision.md) | What we're building and why |
| [User Personas](docs/product/personas.md) | Who we're building for |
| [Use Cases](docs/product/use-cases.md) | How users will use the product |
| [MVP Scope](docs/product/mvp-scope.md) | What's in the first release |
| [Roadmap](ROADMAP.md) | Development phases and timeline |
| [Architecture Overview](docs/architecture/overview.md) | System design and data flow |
| [ADR: Application Stack](docs/adr/0001-application-stack.md) | Why Rust + Qt 6/QML |
| [ADR: Widget Runtime](docs/adr/0002-widget-runtime.md) | Widget execution and isolation |
| [Threat Model](docs/security/threat-model.md) | Security analysis |
| [Test Strategy](docs/testing/test-strategy.md) | How we ensure quality |
| [Wireframes](docs/product/wireframes.md) | UI layout descriptions |

---

## Supported Platforms

| Distribution | Desktop | Session | Status |
|-------------|---------|---------|--------|
| CachyOS | KDE Plasma 6 | Wayland | 🎯 Primary target |
| CachyOS | KDE Plasma 6 | X11 | ✅ Supported |
| Ubuntu 24.04 LTS | GNOME 46 | Wayland | 🎯 Primary target |
| Ubuntu 24.04 LTS | GNOME 46 | X11 | ✅ Supported |
| Arch Linux | KDE Plasma 6 | Wayland | ✅ Supported |
| Fedora 40 | GNOME 46 | Wayland | ✅ Supported |
| Hyprland (Arch) | Hyprland | Wayland | ⚠️ Best-effort |
| Sway (Arch) | Sway | Wayland | ⚠️ Best-effort |

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Phases

- **Phase 0:** ✅ Discovery — product docs, architecture decisions
- **Phase 1 (Current):** 🔄 Application shell — display enumeration, window placement, touch input
- **Phase 2:** 📋 Layout engine — grid layout, widget management, themes
- **Phase 3:** 📋 Core widgets — clock, system metrics, focus timer, media controls
- **Phase 4:** 📋 Integrations — MPRIS, PipeWire, sensors, autostart
- **Phase 5:** 📋 Hardening — performance, stability, packaging
- **Phase 6:** 📋 Public MVP release
- **Phase 7:** 📋 Community widget SDK

See [ROADMAP.md](ROADMAP.md) for details.

---

## License

This project is licensed under either of:

- MIT License ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)
- Apache License 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)

at your option.

### Dependency Licensing Note

This project links against Qt 6, which is available under LGPLv3. Dynamic linking against the system Qt satisfies LGPL obligations. If you statically link Qt, you must comply with LGPL requirements (provide object files for re-linking).

---

## Security

See [SECURITY.md](SECURITY.md) for our security policy and vulnerability reporting process.

---

## Acknowledgments

- Corsair for the Xeneon Edge hardware (this project is not affiliated with or endorsed by Corsair)
- The KDE and Qt communities for excellent Linux desktop frameworks
- The Rust community for a safe systems programming language
- All contributors and early adopters

---

*Xeneon Edge Linux Hub — Your secondary screen, supercharged.*
