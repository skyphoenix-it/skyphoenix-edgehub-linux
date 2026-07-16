# Widget Permissions Model

**Version:** 0.1.0-draft  
**Status:** Phase 0 — Discovery (Design Only; Implementation in Phase 7)  
**Last Updated:** 2026-07-11  

---

## Overview

The widget permissions model defines what capabilities a widget may request and how those capabilities are granted, enforced, and audited. Permissions are designed for community widgets (Trust Level 3) but the model is defined now to ensure the architecture supports it.

> **Note:** Permissions are not enforced in MVP (Phases 1-6) because all widgets are built-in and fully trusted. This document defines the model for Phase 7 (Community Widget SDK).

---

## Design Principles

1. **Deny by Default** — A widget has zero capabilities unless explicitly granted.
2. **User Consent** — Permissions are requested in the widget installation UI; the user must approve.
3. **Least Privilege** — Widgets should request only the permissions they need.
4. **Explainability** — Each permission includes a human-readable description of why it is needed.
5. **Revocability** — Users can revoke any permission at any time; the widget must handle this gracefully.
6. **Auditability** — Permission usage is logged and visible in widget details.
7. **No Silent Escalation** — A widget cannot gain new permissions without user re-approval.

---

## Permission Catalog

### System Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `time.read` | Read current system time and date | Low | Clock, calendar widgets |
| `time.timezone` | Read system timezone | Low | World clock widget |

### Metrics Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `metrics.cpu` | Read CPU utilization | Low | CPU monitor widget |
| `metrics.memory` | Read memory usage | Low | RAM monitor widget |
| `metrics.disk` | Read disk usage statistics | Low | Disk space widget |
| `metrics.network` | Read network throughput | Low | Network monitor widget |
| `metrics.temperature` | Read temperature sensors | Low | Temperature widget |
| `metrics.gpu` | Read GPU utilization and temperature | Low | GPU monitor widget |

### Media Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `media.control` | Control media playback (play, pause, skip) | Low | Media control widget |
| `media.metadata` | Read current track metadata (title, artist, album) | Low | Now-playing widget |
| `media.volume` | Read and set system volume | Medium | Volume control widget |
| `media.devices` | List audio input/output devices | Low | Audio device switcher |

### System Action Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `system.lock_screen` | Lock the system screen | Low | Lock screen button |
| `system.notifications` | Show desktop notifications | Low | Break reminder widget |
| `system.clipboard.read` | Read from system clipboard | Medium | Clipboard watcher |
| `system.clipboard.write` | Write to system clipboard | Medium | Quick-copy widget |

### Filesystem Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `filesystem.read` | Read files from specified paths | High | Config file reader, log viewer |
| `filesystem.write` | Write files to specified paths | Critical | Note-taking widget, data export |

### Execution Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `execution.command` | Execute approved shell commands | Critical | Custom launcher, automation |
| `execution.application` | Launch .desktop applications | Medium | Application launcher |

### Network Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `network.http` | Make HTTP/HTTPS requests | High | Weather, RSS, web APIs |
| `network.websocket` | Open WebSocket connections | High | Real-time data feeds |

### Process & Window Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `process.list` | List running processes | Medium | Gaming profile auto-switch |
| `process.info` | Read process information (PID, name, CPU, memory) | Medium | Per-app resource monitor |
| `window.list` | List open windows | Medium | Application-aware dashboard |
| `window.title` | Read window titles | Medium | Activity tracking |

### Hardware Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `hardware.openlinkhub` | Access OpenLinkHub device data | Medium | Cooling/fan monitor |
| `hardware.sensors` | Access raw hardware sensors | Medium | Advanced sensor widget |

### Personal Data Permissions

| Permission | Description | Risk Level | Example Use |
|-----------|-------------|------------|-------------|
| `personal.calendar` | Read calendar events | High | Calendar agenda widget |
| `personal.location` | Read approximate location | Medium | Weather widget |

---

## Permission Request Flow

```
1. Widget developer declares permissions in manifest:

   permissions:
     - time.read
     - metrics.cpu
     - media.control

2. User installs widget → sees permission request:

   ┌─────────────────────────────────────┐
   │  "CPU Monitor" wants to access:     │
   │                                     │
   │  ✓ Read CPU utilization             │
   │    Needed to display CPU usage      │
   │                                     │
   │  ✓ Read system time                 │
   │    Needed to timestamp readings     │
   │                                     │
   │  [ Deny ]              [ Allow ]    │
   └─────────────────────────────────────┘

3. User approves → permissions granted, widget loaded

4. Widget calls capability API → runtime checks permission:

   fn get_cpu_usage() -> Result<f64, Error> {
       check_permission("metrics.cpu")?;  // Returns Err if not granted
       // ... read from cache ...
   }

5. Permission usage logged: [INFO] widget=cpu-monitor permission=metrics.cpu action=read

6. User can later view/revoke permissions in widget settings.
```

---

## Permission Revocation

When a permission is revoked:

1. Widget receives a `permission_revoked(permission)` signal.
2. Widget must handle this gracefully — show "Permission required" placeholder.
3. Subsequent calls to that capability return `Error::PermissionDenied`.
4. Widget does NOT crash or enter an error state — it degrades.
5. User can re-grant permission at any time.

---

## Widget Update and New Permissions

When a widget is updated and requests new permissions not previously granted:

1. The new permissions are NOT automatically granted.
2. The widget is paused.
3. User is shown the new permission request.
4. If user approves → widget resumes with new permissions.
5. If user denies → widget remains paused until old version is restored or permissions granted.

---

## Permission Audit Log

Each widget's settings page shows:

```
Permission Usage (last 24h):
  time.read            Used 86400 times    Last: 2s ago
  metrics.cpu          Used 43200 times     Last: 2s ago
  metrics.memory       Used 8640 times      Last: 5s ago
```

This transparency helps users identify widgets that are more active than expected.

---

## Implementation Notes (Phase 7)

Permissions will be enforced via the WASM host API:

```rust
// In the WASM host (Rust core)
#[wasm_bindgen]
impl WidgetHost {
    pub fn get_cpu_usage(&self) -> Result<f64, JsValue> {
        self.check_permission("metrics.cpu")
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        Ok(self.sensor_cache.cpu_usage())
    }
}
```

For QML-based trusted widgets (Level 2), permissions are checked in the Rust bridge layer:

```rust
// In the QML-Rust bridge
#[cxx_qt::qobject]
impl CpuWidget {
    #[qinvokable]
    fn get_cpu_usage(&self) -> Result<f64, String> {
        self.permissions.check("metrics.cpu")
            .map_err(|e| e.to_string())?;
        Ok(self.core.cpu_usage())
    }
}
```

