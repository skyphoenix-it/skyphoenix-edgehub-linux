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
  all fixed. The Dashboard now also fades a removed tile out (on `motionRemove`,
  previously defined and unused), fades an added tile in at its slot (on
  `motionAdd`), and eases the edit-mode "Add widget" slot like a tile. Open:
  the same exit/entrance gap still exists in the Manager's `EdgeClone` (its
  reorder eases, but a removed tile still pops). None of the motion work is
  verified on the real device — the offscreen harness cannot instantiate `qrc:`
  widgets, so delegate survival is asserted via the Loader, not the widget.
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
- ~~The Manager's About button opens `"#"`~~ — **FIXED** (`8fa67c9`), and guarded
  by `scripts/check_ui_links.sh`. Note the lint's first version was itself inert
  (it grepped `openUrlExternally("` and the call was line-wrapped); the negative
  control is the only reason that surfaced.
- ~~`HydrationWidget.qml:260` hard-codes `PillButton { implicitWidth: 170 }`~~ —
  **FIXED** (`b7ef100`), and my framing of it was wrong: the claimed "clips at
  textScale 1.6" does NOT reproduce with today's labels (measured: "Remove" is
  141px at 1.6 vs the 170 literal), which is exactly why the literal survived. The
  bug was latent, awaiting a translation or relabel. 170 was right in VALUE and
  wrong in KIND — the requirement was generosity, not a matched pair — so it is
  now a `PillButton.minWidth` FLOOR: identical rendering today, content wins when
  wider.
- **The `expanded`-vs-size conflation still exists in 7 more widgets**:
  `EndOfDayWidget`, `FocusWidget`, `MoonWidget`, `RightNowWidget`, `NetWidget`,
  `TasksWidget`, and Hydration's own `celebrateLabel` (line 130, `expanded ? 40 :
  20`, with no `wrapMode`/`elide`). `expanded` is the modal overlay, not a size.
  Habit's was fixed in `b7ef100`; these were left to keep that task bounded.
  Worth knowing before touching them: **`full` is not a full screen** — the
  Dashboard hosts the config preview in a pane (~941×456 landscape / ~656×980
  portrait), and the old literals both ignored that box and never noticed when W5
  shrank the pane to 38%.
- **`RamGbOverflow::test_gb_centre_text_fits_ring_interior` fails under a
  DejaVu-only fontconfig** (no emoji fonts). Reproduced on a clean tree, so it is
  pre-existing and not a regression. CI installs `fonts-dejavu-core` and no emoji
  font, so this is close to CI's environment — worth understanding before it
  surfaces there.
- **Wallpaper/theme name collision — it is FIVE names, not three.** Measured
  2026-07-17: the overlap between `Theme.qml`'s modes and `WallpaperCatalog.qml`'s
  items is **aurora, ember, midnight, nebula, sunset**. The W2 audit reported
  Midnight/Nebula/Aurora, which understates it.
  The nuance that matters before anyone "fixes" this: `WallpaperCatalog.qml`'s
  header says the wallpapers are "tuned to the built-in themes", so a shared name
  may be a deliberate PAIRING, not an accident. But the correspondence is partial
  — only 5 of 12 wallpapers match a theme, and 19 of 24 themes have no wallpaper —
  so it reads as a systematic pairing that is not one. There are also THREE
  concepts in play, not two: themes (palettes), `WallpaperCatalog` (bundled
  images) and `BackgroundCatalog` (colour/animated tokens).
  Renaming either set rewrites persisted config values and needs a migration, so
  the cheap fix is UI disambiguation + honest copy about the pairing. **Decide the
  intent first** (is Midnight-the-wallpaper meant to go with Midnight-the-theme?);
  it is a copy question, not an engineering one.
- **`Theme.qml:209` defines `motionRemove: 150` and NOTHING uses it.** The token
  for the missing exit fade already exists. Verified 2026-07-17.
- **AppImage zsync update path: audited 2026-07-17. It does not work today, and
  never has.** Still an **RC exit criterion**. What the audit established:
  - **No release has ever shipped an AppImage or a `.zsync`.** alpha.1 and
    alpha.2 assets confirm it (`gh release view`). The `zsyncmake` branch in
    `scripts/release.sh` has therefore never executed. CI builds an AppImage but
    only uploads it as an expiring workflow artifact; attaching it is a manual
    `--extra` step nobody has done. **Nothing about this path has ever run.**
  - FIXED: the artifact was named from `project(... VERSION 0.1.0)`, which
    CMakeLists.txt freezes across commits — every release would have published an
    identically-named `xeneon-edge-hub-0.1.0-x86_64.AppImage`. `release.sh`
    documents this exact trap for cpack and overrides it; build-appimage.sh had
    the same bug and did not.
  - FIXED: build-appimage.sh never passed `-DXENEON_VERSION_OVERRIDE`, so the
    binary's `appVersion()` came from `git describe` — and `actions/checkout@v4`
    fetches no tags at depth 1, so `--always` degraded it to a bare sha.
    `UpdateChecker.qml` cannot SemVer-order a sha, so it reports "no comparable
    version": **the AppImage could never tell a user an update existed** — in the
    one install kind pointed at the zsync path. Job now pins `fetch-depth: 0`.
  - OPEN (needs a product decision): the AppImage embeds no
    `X-AppImage-UpdateInformation`, so `AppImageUpdate`/`appimaged` cannot update
    it at all and there is no discovery path from an installed AppImage to the
    next `.zsync`. See docs/DISTRIBUTION.md "AppImage + zsync".
  - OPEN: a true download-and-patch test remains unrun. It needs `zsync` + a real
    AppImage; the AppImage build fails on modern-toolchain hosts (linuxdeploy's
    bundled `strip` cannot read `.relr.dyn`), so it can only live in the CI
    `appimage-smoke` job. `scripts/check_appimage_update_contract.sh` guards the
    cross-file invariants offline; it is not a substitute for the round trip.
- First-run wizard welcome still reads "Xeneon Edge Linux Hub" (nominative line
  kept per the rebrand decision — revisit only if a cleaner descriptor is wanted).
- E7 Phase B (keyring) parked by owner decision; branch kept.

## v1.1 (post-1.0, agreed scope)

- Fedora support; Ubuntu 26.04 LTS support.

- **C++-only line coverage is 91.70%** (measured honestly for the first time on
  2026-07-17). `scripts/coverage.sh` now ratchets it at **91**, not the 95 it used
  to claim — that 95 was never enforced because the gate was inert. CI is
  unaffected: it gates Rust ≥95 AND merged ≥95, never C++-only. Two structural
  reasons C++ trails Rust: the D-Bus/QScreen/QProcess glue is deliberately
  `GCOVR_EXCL`-marked, and code compiling ONLY into the `xeneon-edge-hub` target
  is not instrumented at all — `mpris_bridge.cpp`'s 279 uncovered lines were in
  nobody's denominator until 2026-07-17. Raise the ratchet as coverage improves;
  never lower it.

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

**The recurring shape (audited 2026-07-17): a gate reports SUCCESS for the state
where it did no work.** Six found, all green for a long time:

| Gate | How it was inert | Status |
|---|---|---|
| 3 QtTest cases | `test_x_data()` = data provider for a `test_x()` that never existed | fixed `2717f84` |
| `coverage.sh` C++ gate | gcovr arg misparse → `n/a` → the gate skipped **itself** | fixed `69a0484` |
| `qml_coverage.py` | empty matrix scored **100%**; a typo'd source dropped 24 behaviors with no coverage drop | fixed `8b09f9e` |
| `check_ui_links.sh` | grepped a pattern that was line-wrapped in its own target | fixed on arrival |
| `check_live_tests.sh`, `check_doc_links.sh` | reported OK on an **empty tree** | fixed `92490f9` |

**The fix is always the same: a gate must assert its own subjects exist.**
`scripts/check_no_raw_xhr.sh` is the model — it checks "the gate must still own
exactly one construction site", so it fails rather than going quiet if its pattern
stops matching. Count subjects; print the count in the OK line; make zero fatal.

Open follow-up: no mechanism forces the fail-on-violation proof for tests outside
the `_data` trap. Candidate: require new guards to record their evidence (the
sabotage tried, and that it went red) in the PR/commit body — every agent this
session was asked to do exactly that, and it caught real defects in *their own*
work four separate times.
