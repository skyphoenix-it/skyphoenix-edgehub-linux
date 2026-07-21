# Architecture Overview

**Version:** 0.1.0-draft
**Status:** Phase 0 - Discovery
**Last Updated:** 2026-07-11

---

## High-Level Architecture

Xeneon Edge Linux Hub follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────┐
│                     APPLICATION LAYER                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │  First-  │  │ Dashboard│  │ Settings │  │ Diagnostics │  │
│  │  Run     │  │  Manager │  │  Manager │  │   Screen    │  │
│  │  Wizard  │  │          │  │          │  │             │  │
│  └──────────┘  └──────────┘  └──────────┘  └────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                       UI LAYER (QML)                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Theme System  │  Layout Engine  │  Widget Containers │   │
│  │  (Dark/Light/  │  (Grid/Stack/   │  (Loader/Error    │   │
│  │   OLED/HC)     │   Responsive)   │   Boundaries)     │   │
│  └──────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                      CORE LAYER (Rust)                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐   │
│  │  Widget  │ │  Config  │ │  Display │ │   Event Bus   │   │
│  │ Lifecycle│ │  Manager │ │  Manager │ │  (Post-MVP)   │   │
│  │  Manager │ │          │ │          │ │               │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐   │
│  │ Logging  │ │ Permission│ │  Update  │ │  Diagnostics │   │
│  │ (tracing)│ │  Manager  │ │  Checker │ │   Collector  │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                   INTEGRATION LAYER (Rust)                   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐   │
│  │  System  │ │  MPRIS   │ │ PipeWire │ │   Display    │   │
│  │  Sensors │ │  Adapter │ │  Adapter │ │   Detector   │   │
│  │  (/proc, │ │  (D-Bus) │ │ (Pulse/  │ │  (udev, Qt)  │   │
│  │   /sys)  │ │          │ │  PipeWire)│ │              │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                    │
│  │   GPU    │ │  OpenLink│ │  Desktop │                    │
│  │  Metrics │ │  Hub     │ │  Services│                    │
│  │ (sysfs,  │ │ (Future) │ │(autostart│                    │
│  │  NVML)   │ │          │ │  notifs) │                    │
│  └──────────┘ └──────────┘ └──────────┘                    │
├─────────────────────────────────────────────────────────────┤
│                    PLATFORM LAYER                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Qt 6 (QWindow, QScreen, QTouchEvent, QML Engine)    │   │
│  │  Wayland / X11 Abstraction                            │   │
│  │  XDG Base Directories (config, data, cache, state)   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Layer Responsibilities

### Platform Layer
- **Qt 6 Runtime**: Window management, screen enumeration, touch input, QML rendering
- **Wayland/X11 Abstraction**: Transparent display protocol handling via Qt platform plugins
- **XDG Directories**: Configuration, data, cache, and state storage following FreeDesktop standards

### Integration Layer
- **System Sensors**: Reads CPU, RAM, disk, network, temperature from `/proc`, `/sys`, `hwmon`
- **MPRIS Adapter**: D-Bus client for media player detection and control
- **PipeWire/PulseAudio Adapter**: Volume control and audio device management
- **Display Detector**: Monitors display hotplug via udev or Qt events
- **GPU Metrics**: Vendor-specific GPU telemetry (sysfs for AMD/Intel, NVML for NVIDIA)
- **OpenLinkHub**: Optional integration for Corsair hardware (future)
- **Desktop Services**: Autostart, notifications, screen locking

### Core Layer
- **Widget Lifecycle Manager**: Load, init, update, pause, resume, teardown widgets
- **Config Manager**: Read/write versioned configuration; migration; backup
- **Display Manager**: Select target display; handle connect/disconnect; EDID matching
- **Event Bus**: Publish/subscribe for inter-widget communication (post-MVP)
- **Logging**: Structured logging via `tracing` crate
- **Permission Manager**: Declare, request, check, revoke widget permissions (post-MVP)
- **Update Checker**: Optional new-version notification
- **Diagnostics Collector**: Gather system info for diagnostics screen

### UI Layer
- **Theme System**: Dark, light, OLED, high-contrast with customizable accent colors
- **Layout Engine**: Responsive grid and stack layouts; widget position/size management
- **Widget Containers**: QML Loader components with error boundaries and timeout guards

### Application Layer
- **First-Run Wizard**: Display selection, starter layout, autostart configuration
- **Dashboard Manager**: Page management, view/edit mode switching, profile switching
- **Settings Manager**: Categorized settings UI with search
- **Diagnostics Screen**: System info, widget status, integration status, recent errors

---

## Component Interaction Flow

### Startup Sequence
```
1. main() → ConfigManager.load()
2. ConfigManager → if first run: FirstRunWizard.show()
3. DisplayManager → enumerate screens → select target
4. WindowManager → create borderless QWindow on target screen
5. QML Engine → load main dashboard QML
6. WidgetManager → load configured widgets → init each
7. Integrations → connect MPRIS, PipeWire, sensors (async, non-blocking)
8. Dashboard → render → enter View mode
```

### Widget Rendering Cycle
```
1. WidgetManager.update_all(delta_time)
2. For each Active widget (in priority order):
   a. Check update interval → skip if not due
   b. Call widget.update(delta) [with timeout guard]
   c. Widget reads data from Integration layer
   d. QML bindings automatically reflect new data
   e. GPU renders updated QML scene
3. If widget update exceeds timeout → log warning → throttle
4. If widget throws error → error boundary → error placeholder
```

### Display Hotplug Handling
```
1. Qt QScreen added/removed signal
2. DisplayManager → compare to target identity (EDID hash)
3a. Target removed → hide dashboard → notify user
3b. Target added → match by EDID → reopen dashboard
3c. Unknown display added → ignore (not our target)
4. Settings → persist new display state
```

---

## Data Flow

### Configuration Flow
```
User changes setting
  → Settings UI (QML)
  → ConfigManager (Rust, via cxx-qt)
  → Validate (schema check)
  → Backup old config
  → Write new config (TOML/JSON)
  → Notify subscribers (WidgetManager, ThemeManager, etc.)
  → UI updates reactively
```

### Sensor Data Flow
```
/proc, /sys, hwmon, D-Bus, NVML
  → Sensor adapters (Rust, async, thread pool)
  → Parse structured data
  → Cache latest values (Arc<RwLock<SensorCache>>)
  → Widget reads from cache (no I/O on UI thread)
  → QML binding updates
  → GPU renders updated widget
```

### MPRIS Media Flow
```
D-Bus session bus
  → MPRIS adapter (Rust, async)
  → Player detection (NameOwnerChanged signal)
  → Properties fetch (Metadata, PlaybackStatus, etc.)
  → Cache in MPRIS state struct
  → Widget reads from cache
  → User taps control → adapter sends D-Bus method call
  → QML updates metadata display
```

---

## Key Design Decisions

| Decision | Rationale | ADR |
|----------|-----------|-----|
| Rust + Qt 6/QML stack | Best multi-monitor, touch, Wayland support with native performance | ADR-0001 |
| Hybrid widget runtime | Native QML for built-in widgets, WASM sandbox planned for community | ADR-0002 |
| Sensor data caching | Avoids I/O on UI thread; enables configurable polling intervals | This doc |
| EDID-based display identity | Survives connector changes; resilient across reboots | This doc |
| TOML configuration | Human-readable, versioned, supports migrations | This doc |
| tracing crate for logging | Structured, performant, ecosystem standard for Rust | This doc |
| XDG directory compliance | Industry standard for Linux application data | This doc |
| cxx-qt for Rust/Qt bridge | Safe Rust↔C++ interop maintained by KDAB (Qt experts) | ADR-0001 |

---

## Threading Model

```
┌─────────────────────────────────────────┐
│ Main Thread (Qt Event Loop + QML)       │
│ - UI rendering                          │
│ - Touch/input handling                  │
│ - Widget update() calls (time-guarded)  │
│ - QML bindings                          │
├─────────────────────────────────────────┤
│ Integration Thread Pool (async tokio)   │
│ - Sensor polling (/proc, /sys, hwmon)   │
│ - D-Bus communication (MPRIS)           │
│ - PipeWire/PulseAudio                   │
│ - Display monitoring (udev)             │
│ - File I/O (config, logs)               │
├─────────────────────────────────────────┤
│ WASM Thread Pool (Phase 7+)             │
│ - Community widget execution            │
│ - Sandboxed, resource-limited           │
└─────────────────────────────────────────┘
```

**Principle:** Never block the main thread. All I/O, polling, and external communication happen on background threads. Data is shared via `Arc<RwLock<T>>` or message passing.

---

## Configuration Schema (Conceptual)

```toml
[application]
version = 1
first_run_complete = true

[display]
target_edid_hash = "abc123def456"
target_connector = "DP-1"
fallback_behavior = "hide"  # hide | notify | ask

[startup]
autostart = true
reconnect_on_hotplug = true

[dashboards.default]
orientation = "landscape"  # landscape | portrait
pages = ["main", "gaming"]

[dashboards.default.pages.main]
layout = "grid"
columns = 8
rows = 3

[[dashboards.default.pages.main.widgets]]
id = "clock-1"
type = "clock"
position = { column = 0, row = 0 }
size = { width = 2, height = 1 }
config = { format = "24h", show_seconds = false }

[theme]
mode = "dark"  # dark | light | oled | high_contrast
accent_color = "#4A90D9"
reduced_motion = false

[integrations.mpris]
enabled = true

[integrations.sensors]
cpu_poll_interval_ms = 2000
memory_poll_interval_ms = 5000
temperature_poll_interval_ms = 5000

[logging]
level = "info"  # error | warn | info | debug | trace
file_path = ""  # empty = default XDG location
```

---

## Error Handling Strategy

```
Error Severity          Action
─────────────────────────────────────────────
Fatal (app crash)       Watchdog process restarts app, restores state
Critical (integration)  Degrade gracefully, show "unavailable" in UI
Error (widget crash)    Error boundary catches, show placeholder
Warning (slow widget)   Log, throttle update rate
Info (normal ops)       Structured log, no user-visible impact
Debug/Trace             Development only, verbose logging
```

---

## Security Boundaries

```
┌────────────────────────────────────────────┐
│ TRUSTED ZONE (Application Process)         │
│ - Rust core (full system access)           │
│ - Built-in QML widgets (full API access)   │
│ - Config Manager (file read/write)         │
│ - Integration adapters (D-Bus, /proc, etc) │
├────────────────────────────────────────────┤
│ RESTRICTED ZONE (Phase 7+)                 │
│ - WASM community widgets                   │
│ - Capability-based API (explicit grants)   │
│ - Resource limits (CPU, memory)            │
│ - No filesystem, network, or process access│
│   unless explicitly permitted              │
└────────────────────────────────────────────┘
```

See [Threat Model](../security/threat-model.md) for detailed analysis.

---

## Technology Dependencies

### Runtime Dependencies
- Qt 6.5+ (QtQuick, QtWayland, QtDBus, QtSvg)
- Linux kernel 5.15+ (for /proc, /sys, hwmon interfaces)
- Wayland 1.20+ or X11 (via Qt platform abstraction)
- D-Bus session bus (for MPRIS, notifications)
- PipeWire or PulseAudio (for volume control)

### Build Dependencies
- Rust 1.75+ (stable)
- C++17 compiler (GCC 12+ or Clang 16+)
- CMake 3.22+
- Qt 6.5+ development headers
- Corrosion (CMake Rust integration)
- cxx-qt or cxx crate

### Optional Build Dependencies
- NVML development headers (for NVIDIA GPU support)
- OpenLinkHub API headers (future)

---

## Repository Structure Mapping

```
xeneon-edge-linux-hub/
├── app/                  # Application entry point, CLI parsing
├── core/                 # Core library (Rust)
│   ├── src/
│   │   ├── config/       # Config manager, schema, migration
│   │   ├── display/      # Display manager, EDID parsing
│   │   ├── widget/       # Widget lifecycle manager
│   │   ├── event/        # Event bus (post-MVP)
│   │   ├── logging/      # Tracing setup
│   │   └── diagnostics/  # Diagnostics collector
│   └── Cargo.toml
├── ui/                   # QML UI layer
│   ├── qml/
│   │   ├── main.qml      # Main dashboard
│   │   ├── themes/       # Theme QML files
│   │   ├── layouts/      # Layout QML components
│   │   ├── components/   # Shared UI components
│   │   └── wizard/       # First-run wizard QML
│   ├── src/              # C++ or Rust QML bindings
│   └── CMakeLists.txt
├── widgets/
│   ├── built-in/         # Built-in widget QML + Rust backing
│   ├── examples/         # Example widgets for SDK (Phase 7)
│   └── sdk/              # Widget SDK crate (Phase 7)
├── integrations/         # Integration adapters (Rust)
│   ├── system/           # /proc, /sys, hwmon sensors
│   ├── mpris/            # MPRIS D-Bus client
│   ├── pipewire/         # PipeWire/PulseAudio adapter
│   ├── amd/              # AMD GPU metrics
│   ├── nvidia/           # NVIDIA GPU metrics (NVML)
│   └── openlinkhub/      # OpenLinkHub adapter (future)
├── packages/             # Distribution packaging
├── tests/                # Automated tests
├── docs/                 # Documentation
├── scripts/              # Build and dev scripts
├── assets/               # Icons, images, fonts
└── .github/              # CI/CD workflows
```

