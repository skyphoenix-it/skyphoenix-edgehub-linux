# Beta and release gate

**Baseline:** `v1.0.0-alpha.2` is the latest tag.
**Current branch:** unreleased development work.
**Freeze state:** no feature freeze and no code freeze.

There is no `v1.0.0-beta.1` tag in this repository. Earlier copy that described
beta.1 as released or declared the project frozen was premature and has been
removed.

## Implemented on the development branch

- Per-size widget layouts and Manager clarity/smoothness work.
- 30 widgets, 19 presets, 29 themes, 29 accents, 10 animated backgrounds plus
  Gradient.
- Expanded Rust, C++, QML, compositor, runtime, Manager and real-hardware test
  coverage, plus fail-closed release/package contracts.

Implementation does not satisfy the release gate by itself.

## Open release blockers

- [ ] Final integrated Edge input/render/navigation run is green with no skip.
- [ ] Exact-candidate Fedora and Ubuntu package lifecycle jobs are green.
- [ ] AppImage zsync discovery and delta-update are exercised against a
      published release pair.
- [ ] Reproducible performance evidence meets the approved limits; prior
      marketing estimates are not evidence.
- [ ] A 48–72-hour physical-hardware soak completes without leak, crash or
      compositor regression.
- [ ] The exact default theme/font/motion choices are approved.
- [ ] Legal/trademark review of paid Inspired themes is complete.
- [ ] Any payment provider, product, price, refund, support and licence-delivery
      path is real and tested. No store is currently represented as live.
- [ ] All release requirements and defects are closed and documented.

## Freeze sequence

1. **Feature freeze:** only after feature/requirements scope and the product/legal
   decisions above are complete. After this point, only release fixes and release
   documentation may change.
2. **Bug gate:** reproduce, fix and verify every release-blocking finding; re-run
   affected suites and the full candidate suite.
3. **Code freeze:** only after review shows a clean, immutable candidate with no
   release-blocking defect.
4. **Final gate:** run the strict suite, package lifecycle checks, performance
   checks and required hardware evidence from the exact signed candidate.
5. **Release:** sign and publish artifacts, verify them from a clean consumer
   environment, then update public status and launch material.

A passing development run must never be relabelled as a freeze or release after
the fact. Evidence belongs to the exact commit and artifact bytes it tested.
