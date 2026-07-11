# AI Self-Review Guidelines

Review only the current change and code directly affected by it.

The objective is to identify real, actionable problems. Do not invent findings
to populate categories.

## Blocking findings

Report as Blocking when the change introduces or fails to address:

- Compilation, type-checking, linting, or test failures
- Data loss, destructive behavior, or configuration corruption
- Credential, token, secret, or private-data exposure
- Command injection, path traversal, or unsafe process execution
- Arbitrary execution of untrusted widget or plugin code
- UI-thread blocking that can freeze the application or compositor
- Deadlocks, races, memory leaks, process leaks, or missing resource cleanup
- Silent fallback to the primary monitor when the configured display is absent
- Broken display hot-plug, reconnect, rotation, or suspend/resume behavior
- Regressions affecting Wayland, X11, portrait, landscape, or touch operation
- Unhandled absence of optional hardware, sensors, services, or integrations

## Correctness and maintainability

Check that:

- The implementation satisfies the stated acceptance criteria
- The change is limited to the requested task
- Existing architecture and repository conventions are followed
- Public APIs and configuration formats remain compatible unless intentionally changed
- Errors are handled explicitly and produce actionable messages
- Resources are released on failure, shutdown, and cancellation
- Dependencies were not added unnecessarily
- Configuration migrations preserve existing user data
- Generated, vendored, and lock files changed only when required
- Documentation accurately describes the resulting behavior

## Linux and display behavior

For relevant changes, verify:

- KDE Plasma and GNOME implications
- Wayland and X11 behavior
- Portrait and landscape layouts
- Fractional scaling
- Monitor identification without hard-coded connector names
- Display disconnect and reconnect
- Primary-monitor changes
- Suspend and resume
- No repeated compositor-rule manipulation
- No focus stealing or pointer trapping

## Touch and UI behavior

For user-facing changes, verify:

- Touch-only operation remains possible
- Important touch targets are approximately 48 logical pixels or larger
- No essential action depends solely on mouse hover
- Dragging, scrolling, long press, and cancellation behave predictably
- Loading, empty, disconnected, and error states exist
- Reduced-motion and accessibility behavior are preserved
- Animations do not delay input or consume excessive resources

## Performance

Check for:

- Blocking file, network, hardware, database, or process I/O on the UI thread
- Excessive polling or refresh rates
- Unbounded caches, queues, logs, subprocesses, or retry loops
- Repeated expensive parsing or system calls
- Rendering or polling while widgets are hidden
- Unnecessary network access
- Significant idle CPU, memory, GPU, or disk-write regressions

Request measurements when a performance claim is not supported by evidence.

## Testing

Check whether tests cover, where applicable:

- Expected behavior
- Boundary conditions
- Invalid input
- Missing hardware or unavailable services
- Failure and recovery
- Configuration persistence and migration
- Portrait and landscape layouts
- Display hot-plug and reconnect
- Regression risks introduced by the change

Prefer deterministic tests. Do not accept arbitrary sleeps as a substitute for
correct synchronization.

## Output format

Group findings as:

1. Blocking
2. Important
3. Minor
4. Optional

For every finding include:

- File and symbol or approximate line
- Why it matters
- A concrete correction
- Relevant missing test, when applicable

If no meaningful issues are found, state that clearly instead of fabricating
findings.
