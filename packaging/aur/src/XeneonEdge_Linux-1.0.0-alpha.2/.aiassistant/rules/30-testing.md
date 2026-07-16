---
apply: by model decision
instructions: Apply when implementing, changing, reviewing, or generating tests, or when a behavioral change requires verification.
---

# Testing Requirements

Tests should cover where applicable:

- Expected behavior
- Boundary conditions
- Empty, null, and invalid input
- Error and cancellation paths
- Missing hardware or unavailable services
- Configuration persistence and migration
- Resource cleanup
- Concurrency risks
- Regression scenarios

For display-related changes, also consider:

- Portrait and landscape
- Hot-plug and reconnect
- Rotation
- Fractional scaling
- Primary-monitor changes
- Suspend and resume
- Changed connector names

Prefer deterministic tests.

Do not:

- Replace synchronization with arbitrary sleeps.
- Test only private implementation details.
- Weaken production behavior merely to make testing easier.
- claim hardware coverage that was only mocked.