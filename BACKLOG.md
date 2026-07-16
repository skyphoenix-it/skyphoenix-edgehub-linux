# Backlog

Single list of what is open. Until now these were scattered across
`docs/BETA_PLAN.md` (the plan) and `docs/SESSION_HANDOFF.md` (the log), which
meant "what is left?" had no one answer. The plan still owns *strategy*; this
file owns *items*. Optional ideas land here instead of in the code.

Status baseline verified 2026-07-16 against the tree, not against the docs.

## Blocked on Simon (nothing proceeds without these)

| # | Decision | Why it blocks | Notes |
|---|---|---|---|
| D1 | Calm as the default theme? | Ships in the beta's first impression | Current default: dark |
| D2 | Default font: system vs Atkinson Hyperlegible | Same | Atkinson is the a11y-forward pick |
| D3 | Lawyer pass on distro theme naming | This is sold B2B | Partly de-risked already: `ui/qml/Theme.qml:334` keeps distro modes **colour-only** — no logos or wordmarks. The naming is the residual exposure. |
| D4 | Payment provider | Pro cannot sell without it | Deferred from alpha by decision |

## Beta workstreams (`docs/BETA_PLAN.md`)

- **W1 — sizing part 2.** Waves 1–3 landed; 31 widgets carry a `sizes:`
  declaration in `ui/qml/WidgetCatalog.qml`. Open: `habit` should gain `1x1.5`.
- **W2 — Manager UX clarity.** Owner: *"not 100% clear … which setting is
  changing which behavior"*, esp. Design/Layout/Appearance. Audit → restructure.
- **W3 — widget smoothness.** Sensors delegate-churn fixed. Open: structure
  edits rebuild the page so a reorder **teleports** instead of animating;
  `PillButton` clips emoji.
- **W4 — test growth.** Runtime E2E at 6 scenarios. Manager behavior tests wait
  on W2 landing, so they assert the intended UX and not the confusing one.
- **W5 — end-user validation.** Persona walkthroughs after each major merge;
  findings feed W2/W3 as concrete items.

## Known gaps (documented, non-blocking)

- `mpris_bridge.cpp` D-Bus fan-out is uncovered — needs a session bus.
- AppImage zsync update path has never been exercised end-to-end. It is an
  **RC exit criterion**, so it cannot stay untested forever.
  `packaging/appimage/build-appimage.sh` deliberately emits no `.zsync`;
  `scripts/release.sh` does it via `zsyncmake`.
- First-run wizard welcome still reads "Xeneon Edge Linux Hub" (nominative line
  kept per the rebrand decision — revisit only if a cleaner descriptor is wanted).
- E7 Phase B (keyring) parked by owner decision; branch kept.

## v1.1 (post-1.0, agreed scope)

- Fedora support; Ubuntu 26.04 LTS support.

## Test-integrity debt (opened 2026-07-16)

Three tests were found that had **never executed**: QtTest silently treats
`test_x_data()` as the data provider for `test_x()`. One was a weather-egress
guard whose entire job was to fail if the request grew an `&hourly=` series — a
deliberate sabotage proved it never fired; another had expectations stale since
the preset re-authoring and nobody noticed, because it never ran.

`scripts/check_live_tests.sh` now gates that exact class in CI and in
`run_all_tests.sh`. The **general** lesson is not gated and belongs here:

> A test that cannot fail is worse than no test — it spends review trust without
> earning it. A guard is not done until it has been **proven to fail** when the
> thing it guards is violated.

Open follow-up: no mechanism forces that proof for tests outside the `_data`
trap. Candidate: require new guards to record their fail-on-violation evidence
(the sabotage tried, and that it went red) in the PR/commit body.
