---
apply: by model decision
instructions: Apply when work affects displays, windows, touch mapping, startup, shutdown, autostart, suspend, reconnect, Wayland, X11, KDE, GNOME, or Linux integration.
---

# Linux Display and Lifecycle Requirements

Consider:

- KDE Plasma Wayland
- KDE Plasma X11
- GNOME Wayland
- GNOME X11
- Portrait and landscape orientation
- Fractional scaling
- Display hot-plug and reconnect
- Connector changes between boots
- Primary-monitor changes
- Display sleep and wake
- System suspend and resume
- Compositor restart where practical
- Application restart and crash recovery

Requirements:

- Identify displays using resilient metadata where available, not only connectors.
- Never silently open the dashboard on the primary display.
- If the configured display is unavailable, remain hidden or ask the user.
- Keep window placement deterministic without repeatedly moving the window.
- Do not require root privileges during normal operation.
- Treat desktop-specific integrations as optional adapters.
- Preserve configuration when hardware is temporarily unavailable.
- Log actionable diagnostics without generating unbounded logs.