# Troubleshooting Guide

**Work in progress** — This guide will be expanded as common issues are identified during development and testing.

---

## Common Issues

### Application doesn't start

**Symptom:** `xeneon-edge-hub` exits immediately or shows an error.

**Checks:**
1. Verify Qt 6 is installed: `qmake6 --version`
2. Check Wayland session: `echo $XDG_SESSION_TYPE`
3. Run with debug logging: `RUST_LOG=debug xeneon-edge-hub`
4. Check for missing libraries: `ldd $(which xeneon-edge-hub)`

---

### Dashboard opens on wrong monitor

**Symptom:** Dashboard appears on primary monitor instead of Xeneon Edge.

With a saved target display, current builds ordinarily stay hidden when that
display is absent and wait for its reconnect; they never move the fullscreen
dashboard to the primary monitor. Primary-screen fallback is limited to an
unconfigured first run where no Edge-like display can be auto-detected. An
explicit `--reset-wizard` opens only a windowed recovery wizard on primary.

**Fixes:**
1. Open Settings → Display → reselect target display.
2. If display not listed, check cable connections.
3. Re-run first-run wizard: `xeneon-edge-hub --reset-wizard`

---

### Touch input not working

**Symptom:** Dashboard visible but touchscreen doesn't respond.

**Checks:**
1. Verify touch device is detected: `libinput list-devices`
2. Check touchscreen is mapped to correct display in desktop settings.
3. In KDE: System Settings → Input Devices → Touchscreen → Map to output.
4. In GNOME: Settings → Displays → Touchscreen mapping.

---

### Dashboard hidden and won't reappear

**Symptom:** After disconnecting/reconnecting display, dashboard stays hidden.

The Hub always hides immediately when its target display is removed, including
for `notify` and `ask` fallback policies. This prevents the compositor from
moving the fullscreen dashboard onto the primary monitor. A matching display is
shown again only when reconnect is enabled; `ask` also records that display
selection is required in the Manager.

**Fixes:**
1. Check if display is detected: open Settings from primary monitor.
2. If display is listed but dashboard hidden: toggle "Reopen on reconnect" off and on.
3. Open the Manager's Display settings and reselect the attached target.
4. Run `xeneon-edge-hub --reset-wizard` to open the windowed recovery wizard on
   the primary display while keeping the rest of the configuration.

---

### High CPU usage

**Symptom:** Application uses more than 5% CPU at idle.

**Checks:**
1. Turn off animated backgrounds and widget glow.
2. Remove updating widgets one by one to identify the workload.
3. Run from a terminal with `RUST_LOG=debug` and inspect the output.
4. Compare with a session-only safe-mode launch: `xeneon-edge-hub --safe-mode`.

The current development build does not meet its formal RSS release limits; do
not treat the published thresholds as a troubleshooting promise until a candidate
passes them.

---

### Memory usage grows over time

**Symptom:** RAM usage increases continuously.

**Fixes:**
1. Enable safe mode to disable all widgets, then re-enable one by one.
2. Check for widgets with graph/chart history — reduce retention.
3. Restart application: memory leak may be in a specific widget.
4. Report the issue with memory profiling data.

---

### Application crashes on startup

**Symptom:** SIGSEGV or panic on launch.

**Fixes:**
1. Try safe mode: `xeneon-edge-hub --safe-mode`
2. Reset all configuration: `xeneon-edge-hub --reset`
3. Check for corrupted config: `cat ~/.config/xeneon-edge-hub/config.toml`
4. If resetting, keep the `config.toml.bak` path printed by `--reset`; it is the
   recovery copy of the discarded configuration.

---

### After system suspend/resume, dashboard is black

**Symptom:** Dashboard window visible but shows black content.

**Fixes:**
1. Restart the application.
2. Re-run display recovery with `xeneon-edge-hub --reset-wizard` if the target is
   no longer matched.
3. Record the compositor, GPU driver and session type when reporting the issue;
   GNOME and X11 are not currently advertised without candidate evidence.

---

## Diagnostic Commands

```bash
# Show application version
xeneon-edge-hub --version

# Show diagnostic info
xeneon-edge-hub --diagnostics

# Reset all settings
xeneon-edge-hub --reset

# Start in safe mode
xeneon-edge-hub --safe-mode

# Run first-run wizard again
xeneon-edge-hub --reset-wizard

# Open a decorated recovery/debug window
xeneon-edge-hub --windowed
```

`--diagnostics` opens the diagnostics view; it does not create an export bundle.
Copy the relevant configuration or terminal output manually after checking it for
secrets.

---

## Getting Help

If the above steps don't resolve your issue:

1. Capture terminal output from `RUST_LOG=debug xeneon-edge-hub --diagnostics` and
   remove any private paths or configured feed URLs before sharing it.
2. Check existing [GitHub Issues](https://github.com/skyphoenix-it/XeneonEdge_Linux/issues).
3. Open a new issue with:
   - Distribution and version
   - Desktop environment and session type
   - Display configuration
   - Application version
   - Steps to reproduce
   - Relevant redacted diagnostic/terminal output
