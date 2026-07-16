# MVP Scope

**Version:** 0.1.0-draft  
**Status:** Phase 0 — Discovery  
**Last Updated:** 2026-07-11  

---

## MVP Goal

Deliver a functional, stable, performant Linux application that transforms the Corsair Xeneon Edge into a useful secondary dashboard. The MVP must be installable by normal users on CachyOS and Ubuntu, work reliably under KDE and GNOME (Wayland and X11), and provide enough built-in widgets to be genuinely useful for productivity, system monitoring, and media control.

## MVP Boundaries

### IN SCOPE

#### Application Shell
- [x] Standalone native application (single binary or minimal bundled runtime)
- [x] Display enumeration (name, manufacturer, model, connector, resolution, orientation)
- [x] First-run wizard for display selection
- [x] Resilient display identity (EDID hash + connector fallback)
- [x] Borderless fullscreen window on selected display
- [x] Portrait (720×2560) and landscape (2560×720) support
- [x] Configurable autostart
- [x] Clean shutdown and restart
- [x] Settings persistence (XDG-compliant)
- [x] Diagnostics screen

#### Layout Engine
- [x] Responsive grid layout
- [x] Widget add, remove, move, resize
- [x] Edit mode (widget actions disabled during editing)
- [x] Undo/redo during edit session
- [x] Orientation-specific layouts
- [x] Multiple dashboard pages
- [x] Page switching via swipe

#### Display Management
- [x] Display disconnect detection and hiding
- [x] Display reconnect detection and recovery
- [x] Notification on primary display when dashboard display missing
- [x] Never silently open on wrong monitor
- [x] Support for different connectors on reconnect

#### Touch Interaction
- [x] Tap
- [x] Long press
- [x] Swipe (page navigation)
- [x] Scroll (within widgets)
- [x] Drag (move widgets in edit mode)
- [x] Minimum 48×48 logical pixel touch targets
- [x] Accidental-touch resistance in view mode

#### Themes
- [x] Dark theme (default)
- [x] Light theme
- [x] OLED black theme
- [x] High contrast theme
- [x] User-defined accent color
- [x] Reduced motion toggle

#### Built-in Widgets — System
- [x] Clock (digital, 12h/24h, timezone support)
- [x] Date (with configurable format)
- [x] CPU usage (percentage, optional per-core, optional graph)
- [x] CPU temperature (via hwmon)
- [x] RAM usage (percentage, absolute GB)
- [x] Disk usage (per-mount configurable)
- [x] Network throughput (up/down, per-interface configurable)

#### Built-in Widgets — Productivity
- [x] Focus timer (configurable duration, count-up or count-down)
- [x] Current goal (single text field, editable)
- [x] Top-three priorities (editable checklist)
- [x] Quick note (scratchpad, auto-saves)
- [x] Break reminder (configurable interval)

#### Built-in Widgets — Media
- [x] MPRIS media control (play/pause, prev/next, progress, track info)
- [x] Volume control (via PipeWire/PulseAudio)

#### Built-in Widgets — Controls
- [x] Application launcher (.desktop integration)
- [x] Dashboard page switcher
- [x] Lock screen button

#### Widget Infrastructure
- [x] Widget lifecycle management (init, update, teardown)
- [x] Widget error boundaries (crash isolation)
- [x] Disable-on-repeated-failure
- [x] Widget configuration persistence
- [x] Widget minimum/maximum size enforcement

#### Settings
- [x] Display settings (target display, orientation override)
- [x] Appearance settings (theme, accent, motion)
- [x] Dashboard management (pages, layouts)
- [x] Widget management (list, enable/disable, reset)
- [x] Startup settings (autostart, reconnect behavior)
- [x] Performance settings (polling intervals)
- [x] Diagnostics screen (version, system info, resource usage, logs)
- [x] Search within settings

#### Logging & Diagnostics
- [x] Structured logging (JSON or key-value)
- [x] Configurable log level
- [x] Diagnostics export (with secret redaction)
- [x] Clear logs

#### Packaging
- [x] Arch/CachyOS PKGBUILD
- [x] Ubuntu/Debian .deb package
- [x] Desktop entry file
- [x] Application icon
- [x] Clean uninstall

#### Documentation
- [x] README with build and install instructions
- [x] CachyOS-specific installation guide
- [x] Ubuntu-specific installation guide
- [x] Widget user guide
- [x] Architecture overview
- [x] Troubleshooting guide
- [x] Security policy
- [x] Contribution guide
- [x] Changelog

#### CI/CD
- [x] Build pipeline (format, lint, test, build)
- [x] Dependency audit
- [x] Documentation build check
- [x] Artifact creation for releases

#### Testing
- [x] Unit tests for core logic
- [x] Integration tests for integrations
- [x] UI tests for critical workflows
- [x] Performance baseline tests

### EXPLICITLY OUT OF SCOPE (MVP)

| Feature | Reason | Target Version |
|---------|--------|----------------|
| Community widget SDK | Requires stable internal APIs first | v1.1 |
| Third-party widget sandbox | Requires SDK + isolation infrastructure | v1.1 |
| Widget marketplace/repository | Requires SDK + community adoption | v1.2 |
| Gaming profile auto-switch | Complex process monitoring; needs careful anti-cheat review | v1.0 |
| Per-game dashboard profiles | Depends on gaming profile auto-switch | v1.0 |
| OpenLinkHub integration | Optional hardware integration; lower priority | v1.0 |
| AMD/NVIDIA/Intel GPU detailed metrics | Complex; basic sysfs/hwmon metrics included in MVP | v1.0 |
| Discord integration | Legal and technical complexity | v1.1+ |
| OBS/stream controls | Niche use case for MVP | v1.1+ |
| Configuration import/export | Nice-to-have, not critical for MVP | v1.0 |
| Web content widget (embedded browser) | Security complexity; needs thorough isolation design | v1.1 |
| Flatpak package | Requires sandbox testing; .deb and PKGBUILD first | v1.0 |
| AppImage | Lower priority than native packages | v1.0 |
| Snap package | Controversial in community; lowest priority | TBD |
| Fedora/openSUSE RPM | Expand after Arch/Ubuntu are stable | v1.0 |
| Nix package | Community-driven; not blocking MVP | TBD |
| On-screen keyboard integration | Complex system integration; basic touch input works without it | v1.0 |
| Multi-touch gestures (pinch, multi-finger) | Nice-to-have; basic single-touch interactions sufficient | v1.0 |
| Calendar agenda widget | Requires calendar backend integration | v1.0 |
| Weather widget | Requires network + API key management | v1.1 |
| Habit tracker widget | Productivity nice-to-have | v1.1 |
| Visual regression tests | Infrastructure complexity; unit/integration tests first | v1.0 |
| 24/72hr/7day soak tests | Important but resource-intensive; basic stability tests in MVP | v1.0 |

## MVP Success Criteria

1. ✅ Installs from a single package on CachyOS
2. ✅ Installs from a single .deb on Ubuntu 24.04 LTS
3. ✅ First-run wizard is touch-operable
4. ✅ Dashboard opens on correct display (portrait and landscape)
5. ✅ Dashboard survives display disconnect and reconnect
6. ✅ Dashboard never opens on wrong monitor
7. ✅ All 15+ built-in widgets function correctly
8. ✅ Idle CPU <1%, RAM <150 MB
9. ✅ No compositor freezes after 1 hour of operation
10. ✅ All settings persist across restarts
11. ✅ Touch-only operation for add/move/resize/config widgets
12. ✅ Widget crash does not crash application
13. ✅ Complete documentation for installation and usage
14. ✅ CI pipeline passes on every commit
15. ✅ Public roadmap available

## MVP Development Phases

See [ROADMAP.md](../../ROADMAP.md) for detailed timeline and phases.

| Phase | Name | Key Deliverables |
|-------|------|-----------------|
| 0 | Discovery | Personas, use cases, architecture ADRs, UI concepts, MVP scope (← CURRENT) |
| 1 | Application Shell | Display enumeration, window placement, touch input, settings persistence |
| 2 | Layout Engine | Grid layout, widget add/move/resize, edit mode, themes, pages |
| 3 | Core Widgets | Clock, system metrics, focus timer, goals, checklist, media controls |
| 4 | Integrations | MPRIS, PipeWire, sensors, autostart |
| 5 | Hardening | Performance optimization, display reconnection, packaging, documentation |
| 6 | Public MVP Release | Signed packages, release notes, public roadmap |

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Qt licensing complexity with Rust bindings | Medium | High | Evaluate pure C++ Qt if Rust bindings are immature |
| Wayland protocol limitations for window placement | High | Medium | Layer-shell protocol; X11 fallback path |
| Touchscreen mapping varies by compositor | High | Medium | User-assisted mapping wizard; libinput analysis |
| EDID not available on some displays | Low | Medium | Fallback to connector name; manual identification |
| MPRIS D-Bus instability with some players | Medium | Low | Graceful degradation; timeout handling |
| Performance target (150MB RAM) too aggressive for Qt+QML | Medium | Medium | QML profiling; lazy widget loading; static builds |
| CachyOS packaging differences from Arch | Low | Low | Test on both; document differences |
| Ubuntu 24.04 Qt version too old | Medium | Medium | Static Qt build or Flatpak fallback |

