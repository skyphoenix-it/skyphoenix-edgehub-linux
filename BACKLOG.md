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
- **W3 — widget smoothness.** Sensors delegate-churn, the Dashboard reorder
  teleport, the EdgeClone reorder teleport, and PillButton's glyph scaling are
  all fixed. The Dashboard now also fades a removed tile out (on `motionRemove`,
  previously defined and unused), fades an added tile in at its slot (on
  `motionAdd`), and eases the edit-mode "Add widget" slot like a tile. Open:
  the same exit/entrance gap still exists in the Manager's `EdgeClone` (its
  reorder eases, but a removed tile still pops). None of the motion work is
  verified on the real device — the offscreen harness cannot instantiate `qrc:`
  widgets, so delegate survival is asserted via the Loader, not the widget.
- **W4 — test growth.** Runtime E2E at 6 scenarios. Manager behavior tests wait
  on W2 landing, so they assert the intended UX and not the confusing one.
- **W5 — end-user validation.** Persona walkthroughs after each major merge;
  findings feed W2/W3 as concrete items.

## Known gaps (documented, non-blocking)

- **`--reset` destroys `config.toml` with no backup** (`reset_config()`,
  `core/src/config.rs`). The corruption path always preserves a `.corrupt-*.bak`;
  reset does not. Its non-destructive neighbour is `--reset-wizard` — one word
  apart, and what separates them is the user's entire layout. A mistype is
  unrecoverable. Deliberately NOT pinned by a test: asserting today's behavior
  would make the obvious fix ("back up before reset") fail CI. **Needs a product
  decision from Simon**, not a test. Found while building runtime scenario 06.
- **The Manager half of the single-writer rule is unproven end-to-end.** Runtime
  07 proves the *hub* keeps its half (a pushed layout is persisted by the hub,
  survives SIGKILL+restart, and an empty push writes nothing). That the *Manager*
  does not write `config.toml` while connected is still covered only by
  `tst_manager_backend_sync.cpp`'s FakeHub. The Manager saves only through GUI
  interaction and exposes no headless save hook; adding one would be product code
  written to pass a test. This is the one real gap left in the B5 story.
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
