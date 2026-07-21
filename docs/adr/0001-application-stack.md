# ADR-0001: Application Stack Selection

**Status:** Proposed
**Date:** 2026-07-11
**Decision Maker:** Software Architect
**Consulted:** Security Engineer, Senior Linux Developer, Senior Rust/C++ Developer, Product Manager

---

## Context

We need to select the primary technology stack for Xeneon Edge Linux Hub. The stack must satisfy:

- Native Linux desktop application (not a web server, not Electron, not a browser kiosk)
- Multi-monitor support with reliable display targeting (Wayland and X11)
- Smooth touchscreen interaction on secondary displays
- Minimal resource consumption (<1% CPU idle, <150 MB RAM)
- Widget-based extensibility with future community SDK
- Cross-distribution compatibility (CachyOS, Ubuntu, Arch, Fedora)
- KDE Plasma and GNOME support on both Wayland and X11

## Decision Drivers (Priority Order)

1. Multi-monitor and Wayland support quality
2. Touchscreen input handling quality
3. Idle resource consumption (CPU, RAM, GPU)
4. Widget extensibility and sandboxing feasibility
5. Development velocity and maintainability
6. Packaging and distribution simplicity
7. Community contributor accessibility
8. Long-term ecosystem stability

---

## Options Evaluated

### Option A: Rust + Tauri 2 + Lightweight Frontend (Svelte/SolidJS/Vanilla TS)

**Architecture:** Rust backend with Tauri 2 IPC bridge to a WebView-rendered frontend.

| Criterion | Assessment |
|-----------|------------|
| Multi-monitor / Wayland | ⚠️ Tauri 2 uses WebKitGTK on Linux. WebKitGTK's Wayland support is improving but historically problematic for multi-window and specific-monitor placement. Window positioning on non-primary monitors is limited. |
| Touchscreen | ⚠️ WebView touch handling is inconsistent. Multi-touch gestures are limited. Browser touch events differ from native touch events, causing subtle interaction issues. |
| Idle resource use | ❌ WebKitGTK requires a full web rendering engine. Even a minimal page consumes 80-150MB per WebView. Adding a JS framework inflates this. Target of <150MB total is at risk. |
| Startup time | ❌ WebView initialization is slow (1-3s cold start). JS framework bootstrap adds more delay. |
| Widget extensibility | ✅ Web technologies are the most accessible for community developers. HTML/CSS/JS widgets are standard. |
| Sandboxing | ✅ WebView provides natural isolation between widgets (iframes or separate WebViews). |
| Packaging | ⚠️ Bundling WebKitGTK or depending on system version creates distribution friction. Flatpak likely required. |
| Community access | ✅ Web developers are abundant. Frontend frameworks are well-known. |
| Ecosystem stability | ⚠️ Tauri 2 is relatively new. WebKitGTK API stability is moderate. |

**Idle resource estimate:** 200-350MB RAM, 2-5% CPU
**Verdict:** Does not meet performance targets. WebView overhead is prohibitive for a secondary display.

---

### Option B: C++ or Rust + Qt 6/QML

**Architecture:** Qt 6 C++ core with QML declarative UI. Option for Rust via `cxx-qt` or `qmetaobject-rs` crates.

| Criterion | Assessment |
|-----------|------------|
| Multi-monitor / Wayland | ✅ Qt 6 has excellent multi-monitor support via `QScreen` API. Native Wayland support through Qt Wayland platform plugin. `QWindow::setScreen()` directly targets specific displays. Layer-shell protocol available via `qt6-wayland` for compositor integration. |
| Touchscreen | ✅ Native `QTouchEvent` handling. QML has built-in touch-aware controls. Gesture recognizers (swipe, pinch). Multi-touch support. |
| Idle resource use | ✅ Qt with QML can idle at 80-130MB RAM. QML rendering is GPU-accelerated and efficient when content is static. CPU usage near 0% when idle. |
| Startup time | ✅ Sub-second cold start. No JS engine or WebView to initialize. |
| Widget extensibility | ✅ QML components are natural widgets. `QQmlComponent` dynamic loading. QML plugins for extension. Community developers can write QML widgets. |
| Sandboxing | ⚠️ QML runs in the same process by default. Sandboxing requires additional work (seccomp, separate QML engine in restricted thread/process, or WASM via `qmlwasm`). |
| Packaging | ✅ Qt 6 is widely packaged. Static linking possible. System Qt or bundled. |
| Community access | ⚠️ QML is less known than web technologies. However, QML is declarative and relatively easy to learn. C++ requirement for advanced widgets may deter some. |
| Licensing | ⚠️ Qt is LGPLv3/GPLv3 + commercial. LGPL is compatible with our open-source goals. Static linking requires LGPL compliance (object file availability) or commercial license. |
| Ecosystem stability | ✅ Qt has 25+ years of stability. KDE is built on Qt. Long-term support guaranteed. |

**Idle resource estimate:** 80-150MB RAM, <1% CPU
**Verdict:** Best balance of performance, multi-monitor support, and touch handling. Primary concern is widget sandboxing (addressable) and licensing (manageable with LGPL compliance).

---

### Option C: Rust + Slint

**Architecture:** Rust application with Slint declarative UI.

| Criterion | Assessment |
|-----------|------------|
| Multi-monitor / Wayland | ❌ Slint's multi-monitor support is immature. Setting a window to a specific screen is not a first-class API. Wayland support exists but limited. |
| Touchscreen | ⚠️ Basic touch support. No built-in gesture recognition. Limited multi-touch. Touch target sizing is manual. |
| Idle resource use | ✅ Slint is extremely lightweight. Sub-50MB RAM possible. Near-zero CPU idle. |
| Startup time | ✅ Very fast. Compiled UI. |
| Widget extensibility | ❌ Slint's `.slint` DSL is compiled, not dynamic. Runtime widget loading requires significant custom infrastructure. Community SDK would be limited. |
| Sandboxing | ⚠️ No built-in isolation. Would need custom solution. |
| Packaging | ✅ Single Rust binary. Simple packaging. |
| Community access | ❌ Slint is niche. Small community. Learning curve for custom DSL. |
| Ecosystem stability | ❌ Slint is young (v1.x in 2024). API stability not proven long-term. |

**Idle resource estimate:** 30-80MB RAM, <1% CPU
**Verdict:** Too immature for multi-monitor and touchscreen requirements. Widget extensibility path is unclear. Slint is promising but not yet ready for this use case.

---

### Option D: Flutter for Linux

**Architecture:** Dart + Flutter with Linux desktop embedder.

| Criterion | Assessment |
|-----------|------------|
| Multi-monitor / Wayland | ⚠️ Flutter Linux multi-monitor support is improving but still limited. Window placement on specific monitors is not straightforward. Wayland support is maturing but has gaps. |
| Touchscreen | ✅ Flutter has excellent touch handling built for mobile. Gesture recognizers. Multi-touch. |
| Idle resource use | ❌ Flutter engine is relatively heavy. Typical idle is 150-250MB. Dart VM adds overhead. |
| Startup time | ⚠️ Moderate. Dart VM warmup. Flutter engine initialization. |
| Widget extensibility | ⚠️ Flutter's widget model is good but dynamic loading of external widgets is limited. AOT compilation makes plugin systems harder. |
| Sandboxing | ⚠️ No built-in sandboxing. Would need custom solution. |
| Packaging | ⚠️ Flutter Linux packaging is complex. Large binary size due to Flutter engine bundling. |
| Community access | ✅ Dart/Flutter has a large developer community. |
| Ecosystem stability | ⚠️ Flutter Linux is not a priority for Google. Desktop support lags behind mobile. |

**Idle resource estimate:** 150-300MB RAM, 2-5% CPU
**Verdict:** Resource overhead is too high. Flutter Linux maturity for multi-monitor is insufficient. Packaging complexity is a barrier.

---

### Option E: Rust + GTK 4 + Blueprint/Libadwaita

**Architecture:** Rust with gtk4-rs bindings, GTK 4 widgets, and Blueprint UI description.

| Criterion | Assessment |
|-----------|------------|
| Multi-monitor / Wayland | ✅ GTK 4 has good Wayland support (GNOME's native toolkit). Multi-monitor via GdkMonitor API. |
| Touchscreen | ✅ GTK 4 has gesture support (GtkGestureClick, GtkGestureSwipe, etc.). Touch events are native. |
| Idle resource use | ✅ GTK 4 can be lightweight. 60-120MB RAM typical. |
| Startup time | ✅ Fast startup. |
| Widget extensibility | ⚠️ GTK widgets are compiled (C or Rust). Runtime widget loading requires plugins (libpeas) or scripting (JavaScript via GJS). Complex to manage. |
| Sandboxing | ⚠️ No built-in. Custom solution needed. |
| Packaging | ✅ GTK is ubiquitous on Linux. |
| Community access | ⚠️ GTK development has a steeper learning curve than QML. Rust bindings add another layer. |
| Ecosystem stability | ✅ GTK is mature and stable. GNOME's official toolkit. |

**Idle resource estimate:** 60-150MB RAM, <1% CPU
**Verdict:** Strong technically but widget extensibility story is weaker than Qt/QML. GTK's gesture system is good but QML's declarative approach is more natural for widget dashboards. Libadwaita styling may feel too GNOME-specific.

---

## Decision

**Selected: Option B - Rust + Qt 6/QML (with C++ where Rust bindings are insufficient)**

### Primary Implementation Approach

1. **Core in Rust** using the `cxx-qt` crate for Qt bindings, or `qmetaobject-rs` for lighter integration.
2. **UI in QML** for declarative, GPU-accelerated, touch-friendly interfaces.
3. **Fallback to C++** for Qt integration points where Rust bindings are immature or incomplete. The architecture supports a hybrid Rust/C++ codebase via C FFI boundaries.
4. **Build system: CMake + Corrosion** (CMake module for Rust integration) to handle the hybrid build cleanly.

### Rationale

- **Qt 6 is the only option with proven, first-class multi-monitor support on both Wayland and X11.** `QWindow::setScreen()` and `QScreen` API are exactly what we need.
- **QML's declarative widget system maps directly to our widget dashboard concept.** Widgets are QML components; layouts are QML positioners; themes are QML style properties.
- **Native touch handling** with gesture recognizers eliminates the need for custom touch event processing.
- **Performance targets are achievable** - Qt+QML can idle under 150MB and <1% CPU with proper optimization.
- **Rust for the core** gives us memory safety for all non-UI logic: hardware integration, configuration management, metrics parsing, widget lifecycle, and security boundaries.

### Mitigations for Identified Concerns

| Concern | Mitigation |
|---------|------------|
| Widget sandboxing (same process) | QML widgets are trusted components. For community widgets (Phase 7), implement process isolation via QProcess + restricted child process, or WASM sandbox via a custom QML element. This is documented in ADR-0002. |
| Qt LGPL licensing | Dynamic linking against system Qt satisfies LGPL. For static builds, provide object files for re-linking. Evaluate commercial Qt license only if needed. |
| Rust binding maturity | Use `cxx-qt` for well-supported Qt classes. Wrap less-common Qt APIs in minimal C++ shims with C FFI. Architecture supports this pattern cleanly. |
| Community QML knowledge | QML is more accessible than traditional C++ Qt. Documentation and examples will lower the barrier. Widget SDK will use QML + optional Rust for advanced logic. |

### Alternatives Considered But Rejected

| Option | Primary Rejection Reason |
|--------|-------------------------|
| Tauri 2 + Web Frontend | WebView overhead violates performance targets |
| Slint | Immature multi-monitor and touch support |
| Flutter | High resource overhead; weak Linux multi-monitor |
| GTK 4 + Rust | Weaker widget extensibility story |

---

## Consequences

### Positive
- Excellent multi-monitor and Wayland support out of the box
- Native touch handling reduces custom input code
- QML provides a natural widget development model
- GPU-accelerated rendering with low idle overhead
- Qt's stability and long-term support reduce ecosystem risk
- KDE Plasma (our primary target) is built on Qt - maximum compatibility

### Negative
- Qt licensing requires LGPL compliance diligence
- Rust bindings may need C++ shim code for some Qt APIs
- QML is less known than web technologies for community contributors
- Hybrid Rust/C++/QML build system is more complex than a single-language stack
- Widget sandboxing requires custom implementation (addressed in ADR-0002)
- Larger binary size than pure Rust solutions (but acceptable for desktop)

### Reversal Cost
**Medium-High.** Switching away from Qt after significant QML and C++ code has been written would require rewriting the entire UI layer and significant portions of the integration layer. The Rust core could be preserved. Estimated reversal effort: 3-6 months.

---

## References

- [Qt 6 QScreen API](https://doc.qt.io/qt-6/qscreen.html)
- [Qt 6 QWindow API](https://doc.qt.io/qt-6/qwindow.html)
- [Qt Wayland Compositor](https://doc.qt.io/qt-6/qtwaylandcompositor-index.html)
- [cxx-qt crate](https://github.com/KDAB/cxx-qt)
- [qmetaobject-rs crate](https://github.com/woboq/qmetaobject-rs)
- [Corrosion (CMake + Rust)](https://github.com/corrosion-rs/corrosion)
- [Qt LGPL obligations](https://www.qt.io/licensing/open-source-lgpl-obligations)

