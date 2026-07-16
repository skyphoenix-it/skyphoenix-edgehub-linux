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

**Fixes:**
1. Check if display is detected: open Settings from primary monitor.
2. If display is listed but dashboard hidden: toggle "Reopen on reconnect" off and on.
3. Force reopen from terminal: `xeneon-edge-hub --force-show`
4. Reset display config: `xeneon-edge-hub --reset-display`

---

### High CPU usage

**Symptom:** Application uses more than 5% CPU at idle.

**Checks:**
1. Reduce sensor polling intervals in Settings → Performance.
2. Disable widgets one by one to identify the culprit.
3. Check logs for widget timeout warnings.
4. Enable safe mode: `xeneon-edge-hub --safe-mode`

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
4. Delete config and restart: `rm -rf ~/.config/xeneon-edge-hub/`

---

### After system suspend/resume, dashboard is black

**Symptom:** Dashboard window visible but shows black content.

**Fixes:**
1. Restart the application.
2. Toggle dashboard visibility in Settings.
3. This may be a compositor/GPU driver issue — try switching between Wayland and X11.

---

## Diagnostic Commands

```bash
# Show application version
xeneon-edge-hub --version

# Show diagnostic info
xeneon-edge-hub --diagnostics

# Export diagnostics bundle
xeneon-edge-hub --export-diagnostics

# Reset all settings
xeneon-edge-hub --reset

# Reset only display settings
xeneon-edge-hub --reset-display

# Start in safe mode
xeneon-edge-hub --safe-mode

# Force show dashboard on primary monitor (emergency)
xeneon-edge-hub --force-show

# Run first-run wizard again
xeneon-edge-hub --reset-wizard
```

---

## Getting Help

If the above steps don't resolve your issue:

1. Export diagnostics: `xeneon-edge-hub --export-diagnostics`
2. Check existing [GitHub Issues](https://github.com/your-org/xeneon-edge-linux-hub/issues)
3. Open a new issue with:
   - Distribution and version
   - Desktop environment and session type
   - Display configuration
   - Application version
   - Steps to reproduce
   - Diagnostics bundle (if safe to share)

