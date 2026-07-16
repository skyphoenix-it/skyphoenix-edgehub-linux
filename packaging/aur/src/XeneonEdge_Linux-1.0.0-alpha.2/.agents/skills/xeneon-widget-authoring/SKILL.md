---
name: xeneon-widget-authoring
description: Create a first-party widget that follows the project's lifecycle, layout, permission, performance, testing, and documentation conventions.
---

# Widget Authoring Workflow

Before implementation:

1. Inspect the existing widget API and similar widgets.
2. Define purpose, inputs, outputs, refresh rate, settings, and permissions.
3. Define portrait and landscape behavior.
4. Define loading, empty, error, and disconnected states.

Implementation requirements:

- Follow the existing widget lifecycle.
- Avoid network, filesystem, command, or process access unless required.
- Request the least privilege possible.
- Bound refresh rates and resource use.
- Stop work when hidden or inactive where appropriate.
- Do not block the UI thread.
- Isolate integration failures.
- Support resizing and orientation changes.
- Add unit and integration tests.
- Document settings, permissions, and limitations.