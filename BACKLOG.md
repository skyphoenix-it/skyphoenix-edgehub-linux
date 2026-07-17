# Backlog

Single list of what is open. Until now these were scattered across
`docs/BETA_PLAN.md` (the plan) and `docs/SESSION_HANDOFF.md` (the log), which
meant "what is left?" had no one answer. The plan still owns *strategy*; this
file owns *items*. Optional ideas land here instead of in the code.

Status re-verified 2026-07-17 against the tree, not against these docs — this
file had already drifted within a day (it still called `--reset` an open decision
after the fix shipped). If an entry here disagrees with the code, the code wins.

## Blocked on Simon (nothing proceeds without these)

| # | Decision | Why it blocks | Notes |
|---|---|---|---|
| D1 | Calm as the default theme? | Ships in the beta's first impression | Current default: dark |
| D2 | Default font: system vs Atkinson Hyperlegible | Same | Atkinson is the a11y-forward pick |
| D3 | Lawyer pass on distro theme naming | This is sold B2B | Partly de-risked already: `ui/qml/Theme.qml:334` keeps distro modes **colour-only** — no logos or wordmarks. The naming is the residual exposure. |
| D4 | Payment provider | Pro cannot sell without it | Deferred from alpha by decision |

## Beta workstreams (`docs/BETA_PLAN.md`)

- **W1 — sizing part 2. DONE.** Waves 1–3 landed; 31 widgets carry a `sizes:`
  declaration in `ui/qml/WidgetCatalog.qml`; `habit` gained `1x1.5` (a real
  transposed 4×7 map, not a stretch).
- **W2 — Manager UX clarity. DONE** (audit: `docs/ux/manager-audit-2026-07-16.md`).
  Scope vocabulary defined, copy made honest, and a silent data-loss bug fixed (a
  typed page name was destroyed because nothing in the pane took focus). Open
  items it raised are listed under "Known gaps" below rather than left implicit.
- **W3 — widget smoothness.** Sensors delegate-churn, the Dashboard reorder
  teleport, the EdgeClone reorder teleport, and PillButton's glyph scaling are
  all fixed. Open: no exit fade when a tile is removed (it pops while its
  neighbours glide; `motionRemove` exists and is unused), no entrance for an
  added tile, and the edit-mode "Add widget" slot still jumps. None verified
  on the real device — the offscreen harness cannot instantiate `qrc:` widgets,
  so delegate survival is asserted via the Loader, not the widget.
- **W4 — test growth.** Runtime E2E now at **9** scenarios (added: `--reset`
  flags, live-push single-writer over the real socket, page-dedup round-trip).
  Manager behavior tests landed with W2. Gates: matrix 100%, Rust+C++ ≥95%.
- **W5 — end-user validation.** Persona walkthroughs after each major merge;
  findings feed W2/W3 as concrete items.

## Known gaps (documented, non-blocking)

- ~~`--reset` destroys `config.toml` with no backup~~ — **FIXED** (`dcdc003`).
  It now copies to `config.toml.bak` first via the already-tested
  `backup_config_of()`, and REFUSES to reset if that copy fails (failing to reset
  is recoverable; resetting without the backup is not). The help text says it
  discards the layout and points at `--reset-wizard`; success names the backup
  path. **If you disagree** — i.e. `--reset` should mean "destroy it, I'm sure" —
  say so and I'll revert; that is the only part of this that was ever a decision.
- **`backup_config()` is still only reached via reset.** The public wrapper had
  ZERO production callers before `dcdc003`; `config.toml.bak` was never written,
  and the corrupt path's careful "never clobber the good .bak" guarded a file that
  did not exist. Reset now writes it, but nothing else does — so the "canonical
  good-config backup" is still not a routine safety net. Worth deciding whether a
  save should ever produce one.
- **The Manager half of the single-writer rule is unproven end-to-end.** Runtime
  07 proves the *hub* keeps its half (a pushed layout is persisted by the hub,
  survives SIGKILL+restart, and an empty push writes nothing). That the *Manager*
  does not write `config.toml` while connected is still covered only by
  `tst_manager_backend_sync.cpp`'s FakeHub. The Manager saves only through GUI
  interaction and exposes no headless save hook; adding one would be product code
  written to pass a test. This is the one real gap left in the B5 story.
- ~~`mpris_bridge.cpp` D-Bus fan-out is uncovered — needs a session bus.~~
  **Done 2026-07-17.** The "needs a bus" framing was wrong for most of it: the
  player-choice policy, the metadata/availability rules and the dirty-check were
  pure logic that merely *sat inside* bus-facing methods and an async lambda.
  They now live in `app/src/mpris_state.{h,cpp}` and are unit-tested with no bus
  at all (`tests/cpp/tst_mpris_state.cpp`, 35 cases, 100% line coverage on the
  extracted logic). No `QSKIP` was used — the test instead points
  `DBUS_SESSION_BUS_ADDRESS` at a nonexistent socket and *asserts* the bridge is
  offline, so it fails loudly rather than skipping if a bus ever appears.
  What genuinely still needs a bus, and is deliberately left to the on-device
  E2E: the async fan-out plumbing itself (`ListNames` → per-player
  `PlaybackStatus` → `GetAll` → `Position`), the `PropertiesChanged`
  subscribe/unsubscribe, the stale-reply identity guards (they need two real
  in-flight replies), and `callPlayer` transport control. Those are marked
  `GCOVR_EXCL` in `mpris_bridge.cpp` with that reason.
- **The Manager's About button opens `"#"`** (`manager/qml/Manager.qml:1220`:
  `Qt.openUrlExternally("#")`) — it silently does nothing. Verified 2026-07-17.
- **`HydrationWidget.qml:260` hard-codes `PillButton { implicitWidth: 170 }`**,
  overriding the content-derived sizing PillButton just gained; it will clip at
  textScale 1.6 with a longer label. Verified 2026-07-17.
- **Wallpaper/theme name collision:** Midnight / Nebula / Aurora are each BOTH a
  theme and a wallpaper, so "Midnight" in the Manager means two different things
  depending on the section. Renaming either set would rewrite persisted config
  values and needs a migration, so the cheap fix is disambiguation in the UI, not
  a rename. Raised by the W2 audit.
- **`Theme.qml:209` defines `motionRemove: 150` and NOTHING uses it.** The token
  for the missing exit fade already exists. Verified 2026-07-17.
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
