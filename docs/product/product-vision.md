# Xeneon Edge Linux Hub — Product Vision

**Version:** 0.1.0-draft  
**Status:** Historical Phase-0 discovery draft — superseded
**Last Updated:** 2026-07-11  

> **Historical document.** The goals below explain the original direction, but
> its platform, packaging, performance and feature statements are not current
> support or release claims. The authoritative requirements and evidence status
> are in [MVP scope and evidence status](mvp-scope.md).

---

## Executive Summary

**Xeneon Edge Linux Hub** is a standalone native Linux application that turns the Corsair Xeneon Edge (and similar secondary touchscreen displays) into a dedicated dashboard surface. It displays configurable widgets for productivity, gaming, and entertainment without requiring a browser, external web server, or Electron runtime.

The application runs as a normal desktop application, places a borderless widget canvas on the user's chosen secondary display, and provides smooth touchscreen interaction optimized for the Xeneon Edge's 2560×720 (landscape) and 720×2560 (portrait) form factors.

## Problem Statement

Secondary touchscreen displays like the Corsair Xeneon Edge lack a first-party Linux software ecosystem. Existing solutions are:

- **Browser-based dashboards** — require a permanently running web server, consume excessive resources, and feel disconnected from the desktop.
- **Electron wrappers** — bundle an entire Chromium runtime, consuming 300–500+ MB of RAM at idle.
- **Windows-only vendor software** — Corsair iCUE and similar tools do not support Linux.
- **DIY scripts** — fragile, require terminal expertise, and do not provide a cohesive user experience.

Linux users with secondary touchscreens have no polished, performant, native option.

## Target Audience

| Persona | Description |
|---------|-------------|
| **Productivity-focused developer** | Uses the Edge to display current task, focus timer, system metrics, and media controls while coding. |
| **ADHD/attention-conscious user** | Needs externalized focus cues without distraction. Benefits from visual priority cards, timers, and calm UI. |
| **Linux gamer** | Wants hardware telemetry (temps, FPS, utilization) on a secondary screen without impacting game performance. |
| **Power user / ricing enthusiast** | Wants a customizable, attractive secondary display that integrates with their desktop environment. |
| **Widget developer** | Wants to build and share custom widgets for a supported platform. |

## Core Value Proposition

1. **Zero-dependency dashboard** — no browser, no web server, no Electron. One native binary.
2. **Minimal resource use** — target <1% CPU and <150 MB RAM at idle.
3. **Purpose-built for touch** — 48×48px minimum touch targets, gesture support, accidental-touch resistance.
4. **Reliable multi-monitor** — the dashboard never silently appears on the wrong monitor.
5. **First-class Linux support** — Wayland and X11, KDE and GNOME, CachyOS and Ubuntu.
6. **Extensible** — built-in widgets today, community widget SDK later.

## Product Principles (Priority Order)

1. **Stability** — the application must not crash, freeze, or leak.
2. **Touchscreen usability** — every interaction must work via touch alone.
3. **Performance** — minimal CPU, GPU, memory, disk, and network use.
4. **Correct multi-monitor behavior** — reliable display targeting across hotplugs, rotations, and sleep/wake.
5. **Security** — widgets are sandboxed; no root required; no arbitrary command execution by default.
6. **Maintainability** — clean architecture, documented decisions, automated tests.
7. **Extensibility** — designed for future third-party widgets.
8. **Visual quality** — premium, calm, readable-at-a-glance design.
9. **Cross-distribution compatibility** — works on CachyOS, Ubuntu, Arch, Fedora, and others.
10. **Ease of installation** — packages for major distributions, no terminal required for basic setup.

## Non-Goals (Explicitly Out of Scope)

- **Not** a browser kiosk or Electron app.
- **Not** a replacement for Corsair iCUE on Windows.
- **Not** a system monitoring daemon — it's a user-facing dashboard.
- **Not** a game overlay or injection tool.
- **Not** a DRM bypass mechanism for streaming services.
- **Not** a medical or therapeutic device.
- **Not** a Wayland compositor or display server.
- **Not** dependent on any specific cloud service.

## Success Criteria (MVP)

1. Installs cleanly on CachyOS and Ubuntu LTS.
2. Runs under KDE Plasma Wayland and GNOME Wayland.
3. Supports portrait (720×2560) and landscape (2560×720) Xeneon Edge layouts.
4. Reliably targets the selected monitor across disconnects and reconnects.
5. Supports touch-only basic operation (add, move, resize, configure widgets).
6. Consumes <1% CPU and <150 MB RAM at idle.
7. Does not freeze the compositor.
8. Includes productivity widgets (clock, focus timer, goals, checklist).
9. Includes system-monitoring widgets (CPU, RAM, temps).
10. Includes media controls (MPRIS).
11. Complete installation and usage documentation.
12. Automated test suite and CI pipeline.
13. Public roadmap and contribution guide.
14. Foundation for future community widget SDK.

## Relationship to Corsair

This project is independently developed. It is not produced, endorsed, or supported by Corsair. The name "Xeneon Edge" is used descriptively to indicate the primary target hardware. The final product name may change after evaluating trademark and branding considerations.

## License

To be determined — likely MIT or Apache 2.0 for the application core, with consideration for LGPL if Qt dependencies require it.
