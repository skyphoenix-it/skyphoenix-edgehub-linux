---
name: xeneon-feature-slice
description: Implement one bounded Xeneon Edge feature from requirements through tests, documentation, and final diff review.
---

# Feature Slice Workflow

1. Read AGENTS.md, applicable ADRs, specifications, and existing tests.
2. Restate acceptance criteria and explicit non-goals.
3. Identify the smallest affected component set.
4. Produce a concise implementation plan.
5. Implement without unrelated cleanup.
6. Add or update focused tests.
7. Validate portrait, landscape, touch, and Linux implications where relevant.
8. Run formatting, static analysis, compilation, and focused tests.
9. Inspect the final diff.
10. Update user and developer documentation when behavior changed.

Conclude with:

- Summary
- Changed files
- Commands executed
- Actual results
- Performance impact
- Security impact
- Known limitations
- Remaining risks