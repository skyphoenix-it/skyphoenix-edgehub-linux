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
- **W3 — widget smoothness. DONE** (pending on-device verification). Sensors
  delegate-churn, the Dashboard reorder teleport, the EdgeClone reorder teleport,
  and PillButton's glyph scaling are all fixed. The Dashboard fades a removed tile
  out (`motionRemove`), fades an added tile in at its slot (`motionAdd`), and eases
  the edit-mode "Add widget" slot. The EdgeClone exit/entrance gap is ALSO closed
  now (`b7c023f` — a removed tile fades, an added one arrives; the earlier "still
  pops" note was stale). None of the motion work is verified on the real device —
  the offscreen harness cannot instantiate `qrc:` widgets, so delegate survival is
  asserted via the Loader, not the widget. **This is the one W-item that genuinely
  needs Simon's eyes on the panel.**
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
- ~~The Manager half of the single-writer rule is unproven~~ — it is proven, the
  entry was stale. `tst_manager_backend_sync.cpp::connectedSaveIsIpcOnlyNoFileWrite`
  drives the real `ManagerBackend` against a `FakeHub` over the actual control
  socket, saves while connected, and asserts the push arrives over IPC AND
  `!QFile::exists(config.toml)` — i.e. the Manager did not write the file. Verified
  fail-on-violation 2026-07-17: reintroducing the second write in the connected
  branch makes the C++ suite go red (1/21 failed); removing it returns to 21/21.
  No GUI or product test-hook was needed — the backend save path is directly
  drivable headlessly. The B5 story is closed on both halves (hub side = runtime
  scenario 07).
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
- ~~The `expanded`-vs-size conflation in 7 more widgets~~ — **FIXED** across
  EndOfDay/Focus/Moon/RightNow (`92a3d2e`) and Net/Tasks/Hydration (`e4db92b`),
  after Habit (`b7ef100`). Each mode-keyed SIZE now derives from the room; genuine
  mode-checks (a `showHeader`, an editor-vs-display view, a composition choice
  like which side peaks sit on) were deliberately KEPT and documented as such;
  several `expanded` terms were outright dead code and removed. `celebrateLabel`
  in Tasks and Hydration gained the missing `wrapMode`/`elide`/bounded width.
  Two honest non-guards were documented rather than faked: Tasks `rowFont` and its
  empty-state line both hit the same cap under the literal and the derived
  formula, so no test can tell them apart — the agents left a comment saying so
  instead of a green-either-way guard. **`full` is not a full screen** (the config
  preview is a pane ~941×456 / ~656×980) is now encoded in the tests.
- **HydrationWidget's expanded overlay overflows its box — IN PROGRESS.** Measured
  2026-07-17 (anchoring on the 110px count text, mapping the ColumnLayout into its
  host): the overlay is **612px** tall at goal 8, **812px** at goal 20, built from
  fixed literals. In the 941×456 landscape preview pane it spills off BOTH ends
  (top −53, bottom 559 at goal 8); and it overruns the real device's 720px
  landscape screen too at goal ≳12 — the count clips off the top, the "Daily goal"
  controls off the bottom (unreachable). Portrait panes fit. A room-derivation fix
  is under way (scale the count/cells/spacing to the box height, both orientations).
  Not a ternary swap — a genuine responsive redesign of the overlay.
- ~~`RamGbOverflow::test_gb_centre_text_fits_ring_interior` fails under a
  DejaVu-only fontconfig~~ — **FIXED** (`18c927f`). It was the real bug, not an
  env quirk: with `theme.fontMono` falling back to a proportional face the ring's
  centre reading rendered 265px into a 227px interior. `Layout.maximumWidth` alone
  is inert once implicitWidth exceeds it (and takes HorizontalFit + elide with it);
  paired with `preferredWidth` it binds. Both gauge texts fixed.
- ~~The identical inert-cap shape latent at BreakWidget/ClockWidget/KpiWidget~~
  — **FIXED** the three real ones (`KpiWidget:291`, `ClockWidget:178`,
  `BreakWidget:282`); `BreakWidget:268` was correctly a non-issue (it WRAPS, which
  binds the cap on its own). No automated guard: verified under a no-mono
  fontconfig, but un-guardable in the default DejaVu-mono suite because the value
  pre-fits by char count — a guard there is inert either way (I wrote one, my
  negative control passed, I removed it). This is the CI font blind spot below.
- **CI has a font blind spot for this class.** CI installs `fonts-dejavu-core`,
  which INCLUDES DejaVu Sans Mono, so a `theme.fontMono`-fallback overflow (the
  gauge bug above) does NOT reproduce in CI — only on a machine whose mono font is
  absent or wider. A width-fit test that is honest across fonts would need to
  either force a fallback or assert the structural cap directly rather than glyph
  width. Worth a decision.
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
- ~~`Theme.qml:209` `motionRemove` is unused~~ — now driving the Dashboard exit
  fade (`Dashboard.qml:764`) since the W3 exit-fade work landed.
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

- ~~`scripts/gen_widgets.py` silently overwrites hand-written widgets~~ —
  **FIXED** (`58a65ee`). It wrote every file with `open(path,'w')` unconditionally;
  a plain run replaced real ~92-line widgets with 20-line stubs (it did, once, to
  RamWidget). Now skips existing files and dead names by default; only `--force`
  overwrites. AGENTS.md's "re-run to regenerate" advice was corrected — it was the
  footgun's instruction manual.

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
