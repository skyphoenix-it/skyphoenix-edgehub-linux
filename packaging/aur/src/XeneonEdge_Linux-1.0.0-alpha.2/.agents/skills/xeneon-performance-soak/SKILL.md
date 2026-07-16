---
name: xeneon-performance-soak
description: Measure idle and active resource use, detect leaks, and prepare reproducible long-running stability tests.
---

# Performance and Soak Workflow

Measure before optimizing.

Record:

- Idle CPU
- Active CPU
- Resident memory
- GPU activity where available
- Thread count
- File-descriptor count
- Child processes
- Network traffic
- Disk writes
- Log growth

Test:

- Visible and hidden dashboard
- Static and animated widgets
- Repeated dashboard switching
- Display reconnect cycles
- Sensor and network failures
- Suspend and resume
- 1-hour smoke soak
- 24-hour soak
- Longer soak when release-critical

Look for unbounded growth and background work while inactive.

Provide commands, baseline, result, interpretation, and regression threshold.