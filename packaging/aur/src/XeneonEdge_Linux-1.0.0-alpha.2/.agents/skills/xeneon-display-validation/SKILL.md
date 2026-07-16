---
name: xeneon-display-validation
description: Validate Linux display targeting, orientation, hot-plug, reconnect, scaling, and lifecycle behavior for secondary touch displays.
---

# Display Validation

Create or execute a validation matrix covering:

- KDE Wayland
- KDE X11
- GNOME Wayland
- GNOME X11
- Portrait
- Landscape
- Fractional scaling
- Display disconnect
- Reconnect to the same port
- Reconnect to a different port
- Primary-monitor change
- Display power cycle
- Suspend and resume
- Application restart
- Missing configured display

The application must not silently open on the primary display.

Separate:

- Automated verification
- Mocked verification
- Manual hardware verification
- Untested scenarios

Do not claim real hardware coverage from mocks.