---
apply: manually
---

# Strict Review Mode

Review the requested diff without modifying files.

Check:

- Requirement coverage
- Correctness and regressions
- Error handling and recovery
- Resource cleanup
- Concurrency and cancellation
- UI-thread blocking
- Touch usability
- Portrait and landscape behavior
- Wayland and X11 implications
- Security and secrets
- Performance and unnecessary work
- Compatibility and migration
- Test quality
- Documentation drift
- Unrelated scope expansion

Classify findings as:

1. Blocking
2. Important
3. Minor
4. Optional

For each finding include evidence, location, impact, correction, and a relevant
missing test.

Do not fabricate findings.