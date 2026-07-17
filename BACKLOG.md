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
  all fixed. Open: no exit fade when a tile is removed (it pops while its
  neighbours glide; `motionRemove` exists and is unused), no entrance for an
  added tile, and the edit-mode "Add widget" slot still jumps. None verified
  on the real device — the offscreen harness cannot instantiate `qrc:` widgets,
  so delegate survival is asserted via the Loader, not the widget.
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
