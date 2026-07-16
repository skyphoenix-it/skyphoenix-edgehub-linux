# ADR-0002: Widget Runtime Architecture

**Status:** Proposed  
**Date:** 2026-07-11  
**Decision Maker:** Software Architect  
**Consulted:** Security Engineer, Plugin/SDK Developer, Senior Rust/C++ Developer  

---

## Context

The Xeneon Edge Linux Hub needs a widget runtime that can:

1. Execute built-in (first-party) widgets with full performance and native UI access.
2. In the future (Phase 7), execute community (third-party) widgets with appropriate isolation.
3. Prevent any single widget from crashing or freezing the entire application.
4. Support widget lifecycle management (load, init, update, render, pause, resume, teardown).
5. Enforce resource limits and permissions.

Widgets are the core value proposition. The runtime architecture must balance performance (for built-in widgets) with security (for future community widgets), without requiring a complete rewrite of the widget system between MVP and v1.1.

## Decision Drivers

1. Widget crash isolation (a widget must not take down the dashboard)
2. UI thread responsiveness (a slow widget must not freeze the UI)
3. Performance (built-in widgets must render with minimal overhead)
4. Future community widget security (sandbox boundaries)
5. Developer experience (widget API must be clean and documented)
6. Implementation complexity (must not over-engineer for MVP)

---

## Widget Trust Levels

We define four widget trust levels:

| Level | Name | Execution Context | Permissions | Examples |
|-------|------|-------------------|-------------|----------|
| 0 | Built-in Native | Same process, same thread | Full (trusted) | Clock, CPU meter, focus timer |
| 1 | First-party QML | Same process, same thread | Full (trusted) | Widgets developed in this repo |
| 2 | Trusted Third-party | Same process, restricted thread | Declared, user-approved | Signed community widgets |
| 3 | Sandboxed Community | Isolated process/WASM | Declared, user-approved, enforced | Unsigned community widgets |

**MVP (Phases 1-6) only implements Levels 0 and 1.** Levels 2 and 3 are designed now to ensure the architecture supports them without a rewrite.

---

## Options Evaluated

### Option A: Single-Process QML with Timeout Guards

All widgets run as QML components in the main rendering thread. A watchdog timer detects widgets that block the event loop for too long.

| Pros | Cons |
|------|------|
| Simplest implementation | No real isolation — a crashing widget crashes everything |
| Best rendering performance (no IPC) | Blocking widget freezes entire UI until watchdog fires |
| No serialization overhead | Watchdog can only kill the whole process, not individual widgets |
| Excellent for MVP speed | Community widget support (Level 3) requires complete redesign |

**Verdict:** Too fragile. A single buggy widget destroys user trust. Rejected.

---

### Option B: QML Widgets in Separate QML Engines (Same Process)

Each widget gets its own `QQmlEngine` instance in the same process. QML engines are isolated from each other (separate JavaScript heaps). Widgets communicate via a C++-mediated event bus.

| Pros | Cons |
|------|------|
| Better isolation than shared engine | Still same process — QML engine crash can still take down app |
| Lower overhead than separate processes | Multiple QML engines increase memory (each ~10-30MB) |
| Widgets can be loaded/unloaded independently | Resource overhead of 25+ widgets may exceed 150MB target |
| Natural QML component model | Complex to manage many engines efficiently |

**Verdict:** Improved but still single-process. Memory overhead is concerning. Rejected for community widgets, acceptable for built-in widgets.

---

### Option C: Separate Processes with QML (QProcess)

Each widget or group of widgets runs in a separate Qt process. Communication via D-Bus, Unix sockets, or shared memory. Main process acts as compositor/manager.

| Pros | Cons |
|------|------|
| True process isolation — widget crash isolated | High memory overhead per widget process (each ~50-80MB for Qt) |
| Can enforce seccomp, cgroups, namespaces per widget | IPC latency for every widget update |
| Perfect for community widgets (Level 3) | Complex lifecycle management |
| Can restart individual widgets | 25+ widgets = 25+ processes = unacceptable resource use |

**Verdict:** Too resource-heavy. 25 widgets would consume 1.2-2GB RAM. Rejected as the primary runtime, but may be used for individual high-risk widgets.

---

### Option D: Hybrid — Trusted QML In-Process + WASM Sandbox for Community

**Architecture:**

- **Levels 0-1 (Built-in, First-party):** QML components in main process, same thread. Direct access to Qt APIs, system integrations, and rendering pipeline. Maximum performance.
- **Level 2 (Trusted Third-party):** QML components in main process, separate thread with restricted QML engine context. Limited API surface.
- **Level 3 (Sandboxed Community):** WebAssembly modules running in a WASM runtime (e.g., `wasmtime`). Widgets compile to `.wasm`, are loaded into a sandboxed WASM instance with a capability-based API. Rendering via a restricted canvas or QML bridge.

| Criterion | Assessment |
|-----------|------------|
| Crash isolation (Level 3) | ✅ WASM sandbox is process-level safe by design. Panic in WASM kills only that instance. |
| UI thread safety | ✅ Community widgets run in WASM runtime on separate thread. Built-in widgets are trusted to not block. |
| Performance (Level 0-1) | ✅ Native QML rendering, no IPC overhead. |
| Resource overhead | ✅ WASM runtime overhead is ~5-15MB per instance. 25 widgets ≈ 125-375MB for community widgets (acceptable for Phase 7). Built-in widgets share QML engine. |
| Developer experience | ⚠️ Community developers must compile to WASM. But WASM supports Rust, C++, Go, and via WASI, many languages. |
| MVP simplicity | ✅ MVP only implements Levels 0-1. No WASM runtime needed until Phase 7. |
| Architecture coherence | ✅ Clean separation. Trust boundary is the WASM sandbox. |

**Verdict:** Best balance. MVP is simple (QML only). Community widget path is clearly defined (WASM). Architecture supports the transition without redesign.

---

### Option E: Lua or JavaScript Sandbox for Community Widgets

Embed a sandboxed Lua (e.g., Luau) or JavaScript (e.g., QuickJS, Deno) runtime for community widgets.

| Pros | Cons |
|------|------|
| Familiar scripting languages | Scripting runtimes need C API bridges to UI |
| Lightweight (Lua <1MB) | No built-in UI toolkit — rendering must be done via bridge to QML |
| Fast startup | Memory safety in C bridging code is error-prone |
| Well-understood sandboxing (Luau) | Two widget models (QML + script) creates fragmentation |
| | Scripts can still block the thread they run on |

**Verdict:** Scripting is appealing for simplicity, but the dual widget model (native QML + scripted) creates API fragmentation and bridging complexity. WASM is more coherent because it compiles to a single target regardless of source language.

---

## Decision

**Selected: Option D — Hybrid Architecture with Trusted QML In-Process + WASM Sandbox for Community Widgets**

### MVP Implementation (Phases 1-6)

```
┌──────────────────────────────────────────┐
│              Main Process                 │
│                                          │
│  ┌────────────┐  ┌────────────┐          │
│  │ QML Engine  │  │ Rust Core  │          │
│  │ (Qt Quick)  │◄─┤ (cxx-qt)   │          │
│  │             │  │            │          │
│  │ Widget QML ─┼──┤ Widget Mgr │          │
│  │ Components  │  │ Config Mgr │          │
│  │             │  │ Integrations│         │
│  │ Layout QML  │  │ Sensors    │          │
│  │ Theme QML   │  │ Logging    │          │
│  └────────────┘  └────────────┘          │
│                                          │
│  All widgets are trusted QML components  │
│  running in the main QML engine.         │
│  Widget lifecycle managed by Rust core.  │
└──────────────────────────────────────────┘
```

### Community Widget Architecture (Phase 7+)

```
┌──────────────────────────────────────────┐
│              Main Process                 │
│  ┌────────────┐  ┌──────────────┐        │
│  │ QML Engine  │  │ WASM Runtime │        │
│  │ (Built-in)  │  │ (wasmtime)   │        │
│  │             │  │              │        │
│  │ Widget QML  │  │ .wasm Widget │        │
│  │ Components  │  │ .wasm Widget │        │
│  └────────────┘  │ .wasm Widget │        │
│                   └──────┬───────┘        │
│                          │                │
│  ┌───────────────────────▼──────────┐     │
│  │      Widget Host API (C API)     │     │
│  │  ┌─────────┐ ┌──────┐ ┌───────┐ │     │
│  │  │ Render   │ │ Data │ │Perms │ │     │
│  │  │ (Canvas) │ │ Feeds│ │Check │ │     │
│  │  └─────────┘ └──────┘ └───────┘ │     │
│  └──────────────────────────────────┘     │
│                                          │
│  WASM widgets get:                       │
│  - Restricted canvas for rendering       │
│  - Capability-based data feeds           │
│  - Declared permissions enforced         │
│  - Resource limits (CPU time, memory)    │
└──────────────────────────────────────────┘
```

---

## Widget Lifecycle (All Levels)

```
  [Registered] ──► [Loaded] ──► [Initialized] ──► [Active]
       ▲                │              │               │
       │                ▼              ▼               ▼
       └────────── [Unloaded] ◄── [Paused] ◄──── [Error]
                                           │
                                           ▼
                                      [Disabled]
```

### Lifecycle States

| State | Description | Transitions |
|-------|-------------|-------------|
| Registered | Widget known to system (from config or manifest) | → Loaded (on dashboard add or startup) |
| Loaded | Widget resources loaded (QML compiled, WASM instantiated) | → Initialized (init callback) |
| Initialized | Widget ready, initial data fetched | → Active (first render) |
| Active | Widget running, receiving updates, rendering | → Paused (page hidden), → Error (crash/timeout) |
| Paused | Widget not visible (on inactive dashboard page) | → Active (page shown) |
| Error | Widget encountered an error | → Active (recovered), → Disabled (too many errors) |
| Disabled | Widget disabled by system or user | → Loaded (manual re-enable) |
| Unloaded | Widget removed from dashboard | → Registered (if config retained) |

### Lifecycle Hooks (Future SDK)

```rust
trait Widget {
    fn init(&mut self, config: WidgetConfig) -> Result<(), WidgetError>;
    fn update(&mut self, delta: Duration) -> Result<(), WidgetError>;
    fn render(&mut self, canvas: &mut WidgetCanvas) -> Result<(), WidgetError>;
    fn pause(&mut self) -> Result<(), WidgetError>;
    fn resume(&mut self) -> Result<(), WidgetError>;
    fn teardown(&mut self);
}
```

---

## Error Handling and Crash Isolation

### MVP (Phases 1-6)

Since all widgets run in-process, isolation is limited:

1. **QML Error Boundary:** QML `Loader` components catch QML-level errors (binding errors, type errors) and display an error placeholder instead.
2. **Update Timeout:** Each widget's `update()` call is timed. If a widget takes >100ms to update, it's logged as a warning. If >1s, it's flagged as slow and throttled.
3. **Crash Recovery:** If the main process crashes (e.g., segfault), a watchdog process (minimal Rust binary) restarts the application and restores the last known state.
4. **Disable-on-Repeated-Failure:** If a widget triggers 3 errors in 5 minutes, it's automatically disabled.

### Post-MVP (Phase 7+)

1. **WASM Sandbox:** WASM widgets run in isolated `wasmtime` instances. A WASM panic is caught and reported; the widget is reloaded.
2. **Resource Limits:** WASM instances have CPU time budgets (via `wasmtime` epoch interruption) and memory limits.
3. **Process Isolation Option:** For high-risk community widgets or embedded web content, a separate `QProcess` with seccomp can be used.

---

## Widget Communication

### MVP

Widgets are independent. No inter-widget communication is supported in MVP. Each widget reads its own data sources.

### Post-MVP

A publish/subscribe event bus allows widgets to communicate:

```rust
// Widget A publishes
event_bus.publish("system.cpu.usage", cpu_percent);

// Widget B subscribes
event_bus.subscribe("system.cpu.usage", |value| { ... });
```

For WASM widgets, the event bus is exposed as a capability:

```rust
// In the WASM host API
fn wasm_subscribe(topic: &str) -> Result<Subscription, Error>;
fn wasm_publish(topic: &str, data: &[u8]) -> Result<(), Error>;
```

Cross-widget communication requires declared permissions.

---

## Consequences

### Positive
- MVP implementation is simple: all widgets are QML, no sandbox overhead.
- Architecture is designed for community widgets from day one — no rewrite needed.
- WASM sandbox is a proven, secure isolation mechanism.
- Clear trust-level model guides implementation and security review.
- Widget lifecycle is well-defined and consistent across all trust levels.

### Negative
- WASM widgets have higher latency than native QML widgets (acceptable for community).
- WASM widget rendering is limited to canvas API unless we build a QML bridge (complex).
- Dual widget model (QML + WASM) means two sets of widget development documentation.
- Event bus adds complexity that must be designed carefully to avoid coupling.

### Reversal Cost
**Low for MVP, Medium post-MVP.** During MVP (Phases 1-6), we're only building Levels 0-1. The WASM architecture can be redesigned in Phase 7 without affecting the MVP codebase, as long as the widget lifecycle traits and configuration schema remain stable.

---

## References

- [wasmtime](https://wasmtime.dev/) — Standalone WASM runtime
- [WASI](https://wasi.dev/) — WebAssembly System Interface
- [wasm-bindgen](https://github.com/rustwasm/wasm-bindgen) — Rust-to-WASM bindings
- [Qt QML Loader](https://doc.qt.io/qt-6/qml-qtquick-loader.html) — Dynamic QML component loading
- [Qt Quick Canvas](https://doc.qt.io/qt-6/qml-qtquick-canvas.html) — 2D canvas for QML

