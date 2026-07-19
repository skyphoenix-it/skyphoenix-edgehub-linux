# TODO — GUI test suite plan + first baseline (2026-07-19)

> Companion to [`MANDATE-gui-testsuite.md`](MANDATE-gui-testsuite.md). **Read the
> mandate first.** This file holds the plan and the measured state. Update the
> checkboxes and the baseline table as work proceeds.

## THE KEY REFRAME — read this before planning anything

**`tests/gui/` is not an empty slot.** It is already **~13,500 lines, ~940 test
functions across 19 files**, covering all 30 widget types, both Manager and Hub
shells, orientation, and dialogs. It had simply **never been run to green**.

So the job is **not** "write a GUI suite from scratch". It is:
1. get the existing suite to a trustworthy baseline,
2. separate real product bugs from harness artifacts,
3. fill the four genuine holes,
4. fix the product bugs.

## FIRST BASELINE — measured 2026-07-19, `-j4`, ~15 min, 0 OOM, 0 sentinel trips

`RUN_MEM_MAX_MB=2048 RUN_AS_MAX_MB=12288 RUN_TIMEOUT=900 ./tests/gui/run_gui_tests.sh --fast -j4`

**TOTALS: pass=1356 fail=210 (20 files).** System memory never moved off 32 GB.

| File | pass | fail | note |
|---|---:|---:|---|
| `tst_gui_mgr_theme_accent` | 34 | **52** | worst ratio |
| `tst_gui_shell_nav_edit` | 56 | **41** | |
| `tst_gui_shell_wallpaper_presets` | 75 | **40** | 1,159 `qrc:` errors in log |
| `tst_gui_mgr_edgeclone_screens_dialogs` | 60 | **28** | |
| `tst_gui_shell_orient_settings` | 54 | **26** | orientation |
| `tst_gui_mgr_nav` | 73 | **11** | |
| `tst_gui_w_media_data` | 114 | 9 | |
| `tst_gui_w_time` | 92 | 1 | |
| `tst_gui_w_focus_habits` | 0 | 0 | **SEGFAULT — core dumped** |
| `tst_gui_mgr_bg_glass_images` | 107 | 2 | |
| all other widget files | ~880 | 0 | widgets are the healthy part |

**The damage is concentrated in Manager + shell + orientation. The 30 widget
files are essentially clean.**

## TRIAGE RESULT — 2026-07-19 (209 failures classified)

An independent triage pass classified every failure group. **Result: 0 confirmed
PRODUCT bugs.** 200 TEST-BUG, 9 UNKNOWN, 0 HARNESS-QRC, 0 HARNESS-STUB.
The qrc noise is ambient — it appears in the logs of the *passing* files too, so
it is NOT the discriminator. My earlier "probably qrc" guess was wrong.

**The load-bearing caveat: the suite is not currently testing what ships.**
~139 of the 209 rows were assertions that never ran against working input
(synthetic clicks, hover, wheel). A real interaction regression would have been
invisible. So this run is evidence for state/layout logic only — NOT for
interaction. Do not read "0 product bugs" as release readiness.

### Fixed this session (1356/210 -> 1412/154, +56 rows)

- [x] **Group A (80 rows) — shell window never mapped, so no synthetic input.**
      `tst_gui_shell_*` set `win.visible = true` while `ui/qml/main.qml:11`
      declares `visibility: Window.Hidden` -> QQC2 "Conflicting properties
      'visible' and 'visibility'" -> window never exposed -> every mouseClick/drag
      test failed while programmatic ones passed. Now `win.visibility =
      Window.Windowed`. Result: `shell_orient_settings` 54/26 -> **79/1**,
      `shell_nav_edit` 56/41 -> **87/10**. Conflict warning gone from all logs.
- [x] **Group J (1 row) — suite ran under Breeze, ships as Fusion.** Both binaries
      call `QQuickStyle::setStyle("Fusion")` (`app/src/main.cpp:271`,
      `manager/src/main.cpp:116`); no runner set it. Now exported in all three
      runners, *before* the `__slot` block so parallel mode inherits it.
      Verified: 0 breeze refs in logs. **Measured impact: zero rows.** Correct in
      principle (the suite must test what ships) but it fixed nothing.

### Group B (20 rows) — STILL OPEN, two hypotheses disproved

`test_wallpaper_changes_background` x18 + 2, all failing the *precondition*
`verify(bd.visible)` in `baselineBackdrop()`.
`ui/qml/Dashboard.qml:165`: `visible: wallpaperSource === "" && theme.decorative
&& dashboard.animatedBg`.
- Tried `store.setAppearance("animatedBg", true)` -> **no change**. Reason found:
  the store->root sync only runs inside `applyAppearance()` at load
  (`Dashboard.qml:530`); the `Connections` block (`:536-546`) is root->store only.
- Tried `win.animatedBackground = true` inside `baselineBackdrop()` (post-load)
  -> **also no change**. So `animatedBg` is not the blocking term.
- `theme.decorative` defaults `true` (`ui/qml/Theme.qml:133`), so that is not an
  obvious blocker either.
- **Next:** instrument `baselineBackdrop()` to print all three terms of the
  `visible` expression plus `bd` itself — one of the assumptions about which
  object `findBackdrop()` returns is probably wrong. Do not guess a fourth time.

## TRIAGE RULE — do not report harness artifacts as product bugs

The suite never had a baseline, so a failure is *not* automatically a product
bug. Classify every one of the 210 before fixing anything:

- **HARNESS-QRC** — the GUI environment cannot resolve `qrc:` paths (the shipped
  `main.qml` `initialItem` is a `qrc:` URL; tests push `Dashboard.qml` by relative
  path instead). Suspected cause of most of the 40 wallpaper/backdrop failures:
  `test_wallpaper_changes_background` fails on its **precondition**
  (`'baseline: the animated backdrop is showing' returned FALSE`,
  `tst_gui_shell_wallpaper_presets.qml:177`) with 1,159 `Cannot open: qrc:` in the
  same log. Almost certainly environment, not product.
- **HARNESS-STUB** — `tests/gui/ManagerHarness.qml:17-64` stubs `ManagerBackend`
  entirely (`screensJson()` → `"[]"`, `metricsJson()` → `"{}"`). Any test needing
  real backend data fails for that reason.
- **TEST-BUG** — e.g. `Cannot assign to non-existent property "contentY"` (×2),
  `Uncaught exception: Cannot call method` (×5). These are authoring errors.
- **PRODUCT-BUG** — the real findings. Fix these.

### Confirmed real findings so far

- [x] **P0 — `tst_gui_w_focus_habits` SEGFAULTS — INVESTIGATED 2026-07-19.**
      Reproduce: `tests/gui/validate_gui_file.sh tests/gui/tst_gui_w_focus_habits.qml`

      **Established facts (each verified, not inferred):**
      - **Perfectly deterministic.** 3/3 runs: `rc=139`, exactly **76** tests
        executed, always crashing on entry to the 77th
        (`test_hydration_config_goal`; last pass is always
        `test_hydration_config_glassml(300)`).
      - **NOT caused by the test bounds.** Re-ran with **no `ulimit -v`** at all:
        still `rc=139`. The AS limit is exonerated — this was the first
        hypothesis and it was wrong.
      - **NOT memory exhaustion.** Peak RSS at crash: **517 MB**. Nowhere near
        any cap. This is not an OOM in disguise.
      - **NOT any single test.** `test_hydration_config_goal`,
        `..._glassml`, `..._title` each **pass cleanly in isolation** (4/4/3
        assertions). The fault requires the cumulative sequence.
      - **Crash site:** `QV4::Runtime::StoreElement::call` →
        `QV4::Object::internalPut` (recursive) → `QV4::Object::insertMember`,
        i.e. the JS engine growing an object's member table during `obj[k] = v`.
      - **Environment:** Qt 6.11.1 (`qt6-declarative 6.11.1-3.1`,
        `qt6-base 6.11.1-1`) — a very new Qt.

      **Classification: NOT yet proven to be a shipped-product bug.** The churn
      driver is `tests/ui/WidgetHarness.qml` — a **test** file — whose `Loader`
      `source` is reassigned once per test (`loadWidget()` sets
      `wh.widgetFile`), 76 times in one process, against a single shared
      `instanceId` (`"test-instance"`). Leading hypotheses, in order:
      1. A Qt 6.11.1 V4/Quick defect triggered by heavy `Loader` source churn.
      2. Accumulation in the shared harness store (`ensureSettings` /
         `patchSettings` / `resetSettings` on one instance id across 76 tests).
      Nothing yet points at `ui/qml/` or `manager/qml/` shipped code.

      **Next steps to finish this:**
      - [ ] Determine whether the crash follows test **count** or hydration
        **content**. (A `qmltestrunner` function-name filter was attempted and
        did not select — `-input FILE Class::func` ran 0 tests, `rc=1`. Find the
        correct filter syntax for 6.11, or bisect by commenting out blocks.)
      - [ ] If count-driven: add a harness reset (destroy/recreate the Loader, or
        `gc()`) every N tests and see if the ceiling moves — that confirms
        accumulation and gives an immediate mitigation.
      - [ ] If it reproduces on a minimal standalone Loader-churn snippet, file
        upstream against Qt 6.11.1 and pin the workaround here.
      - [ ] Check whether other large `tst_gui_w_*` files sit just under the same
        ceiling (they run 87–114 tests and pass, which argues **against** a pure
        count limit and toward hydration/content — worth confirming).

      > Note the counter-evidence already in the baseline: `tst_gui_w_media_data`
      > ran **123** tests and `tst_gui_w_focus_core` **109** without crashing. So
      > a naive "76-test ceiling" is likely wrong; content matters.
- [x] **P1 — Dashboard `dying` rows leak — FIXED 2026-07-19.** Added
      `_sweepStaleDying()` + a `_dyingSince` timestamp map to `pageItem`, swept at
      the top of `_syncPlacements`, with bookkeeping cleared on reap and on
      resurrection. Grace is `max(motionRemove*4, 2000)` ms so it can never race
      a merely-slow fade — it is a backstop for fades that are GONE.
      ~~ORIGINAL:~~ **Dashboard `dying` rows leak.** `ui/qml/Dashboard.qml:851-858` marks a
      row `dying` and relies on `exitFade.onFinished → _reapRow`
      (`Dashboard.qml:1034-1039`). If the delegate dies before the animation
      finishes (page teardown, model reset, racing sync), the row stays in
      `placementModel` **forever** — it matches no placement so both loops skip it.
      `manager/qml/EdgeClone.qml:144-149` has a `placementModel.clear()` safety net
      for exactly this; Dashboard has none. A production leak.

## SAFETY WORK STILL REQUIRED (architect review)

- [x] **FIXED 2026-07-19 — the nested compositors are now INSIDE the bound.**
      `run_one` re-invokes the script in `__slot` mode as the child of
      `run_bounded`; `__slot` starts KWin *and* the runner, so both are
      descendants. Verified empirically: nested compositor's parent chain is
      `bash run_gui_tests __slot` -> `run_bounded` subshell. Display/socket names
      now use `slot % J`, so J files never claim more than J displays. Teardown
      is `kill -9` on `EXIT INT TERM`.
      ~~ORIGINAL:~~ **The nested compositors are OUTSIDE the bound.** `run_one` starts
      `kwin_wayland` *before* calling `run_bounded`
      (`run_gui_tests.sh:103-111` vs `:116-118`), so the compositor is a **sibling**
      of the bounded process, not a descendant: it gets no `ulimit -v`, and
      `_rb_tree_rss_mb` never counts it. Wayland client buffers live in that
      uncounted process. **Fix: restructure so `run_bounded` wraps a shell that
      starts KWin *and* the runner.** Highest-value remaining safety fix.
- [ ] **Compositor count is not bounded by `J`.** `slot` is a monotonic counter
      (`run_gui_tests.sh:130-136`), so each of the 20 files gets its own display
      `:71…:91`. Teardown uses **SIGTERM** (`:124`), contradicting the script's own
      SIGKILL policy at `:69-70`, and a partially-started KWin is never killed
      (`:105-108`). Compositors accumulate across a run. Reuse `slot % J`.
- [ ] **`RUN_TIMEOUT` is not wall-clock.** `run_bounded.sh:94-100` counts ticks of
      `sleep 0.5` + a `ps` scan; under load an iteration exceeds 0.5 s so a 900 s
      timeout silently stretches. Compare against `SECONDS` instead.
- [ ] **No aggregate guard.** N slots each under cap can still collectively
      exhaust the box; `ulimit -v 12288` × 8 = 96 GiB of permitted AS. Add a
      budget derived from `MemAvailable` (not a constant). Note: swap is
      **zram only** (RAM-backed) — there is no soft landing before global OOM.
- [ ] **Ceilings disagree.** `run_ui_tests.sh:30` allows 8192 MB; the GUI suite
      allows 2048. Pick one, define it in `run_bounded.sh`, let callers only lower.
- [ ] Default to `-j4`, not `-j8`, until the compositor is inside the bound.

## COVERAGE GAPS TO FILL (from the audit)

- [ ] **G1 — real Manager binary ↔ real Hub binary over the real IPC socket.**
      *The single largest gap in the tree.* Both halves are proven against
      stand-ins (`tests/cpp/tst_manager_backend_sync.cpp` vs a FakeHub;
      `tests/runtime/run_07` drives the real hub from Python), but the two real
      processes have never been connected. `ManagerHarness.qml` stubs the backend,
      so **no GUI test crosses the socket.**
- [ ] **G2 — `WidgetConfigDialog` field editing.** 15,907 bytes of shipped dialog;
      the GUI suite only asserts it *opens*
      (`tst_gui_mgr_edgeclone_screens_dialogs.qml:1003-1051`). No real field edit.
- [ ] **G3 — EdgeClone drag-reorder / resize handles in a compositor.** Tested
      only offscreen (`tests/ui/tst_edgeclone_drag.qml`) — i.e. exactly where
      pointer physics do not exist. The I-series in gui/ is geometry/pixels only.
- [ ] **G4 — `Diagnostics.qml` (21 KB) and `UserWidgetCatalog.qml` (12 KB) are
      never opened in a compositor.** Third-party widget loading has zero
      real-render coverage.
- [ ] **G5 — orientation is driven only by writing `win.orientationMode`
      directly.** Nothing flips it the way a user does (SettingsPanel / Manager
      orientation chip) and then checks the whole screen for layout breakage.
      The real sensor byte path is covered only in isolation
      (`tst_orientation_byte.cpp`). *Note: orientation is otherwise the
      best-covered area — `tst_gui_shell_orient_settings.qml:302-338` already
      asserts real rendered aspect inversion and page preservation both ways.*
- [ ] **G6 — leak detection built into the suite.** Add a `census(root)` helper to
      `GuiUtil.js` returning `{nodes, models, timers}` (nodes = `walkStats().unique`,
      models = Σ `.count` over reachable ListModels, timers = reachable running
      Timers). Protocol: run action once and discard → `gc()` → census → run N=20 →
      `gc()` → census → assert **equality, not a tolerance**. This catches the
      Dashboard `dying` leak. It does *not* catch the walk bugs — that is
      `tst_gui_util_walk.qml` + `check_tree_walks.py`, which are complementary.
      Do **not** assert on RSS inside QML (10 Hz Sparkline string churn at
      `Sparkline.qml:86-92` makes it non-deterministic); put RSS trending in
      `run_bounded.sh` as an advisory `RSSPEAK:` line instead.
- [ ] **G7 — `objectName` seams + a lint.** `tests/ui/tst_manager.qml:140-153`
      still duck-types `_store`, `_theme`, `_confirm`, `_nav`. The repo already
      hit this exact bug once (a duck-typed ListModel silently matched EdgeClone's
      model). Same class as the closed `_data` trap — close it the same way.
- [ ] **G8 — delete or rewrite `tests/ui/tst_manager.qml:172`
      `test_four_tabs_switch`**: it assigns `currentIndex` then compares that same
      property to what it just assigned. Trivially true; would pass on a
      completely broken tab bar. Real coverage already lives at
      `tests/gui/tst_gui_mgr_nav.qml:137-217`.

## PHASE STATE

- [x] Phase 0 — recovery + hardening (3 leaks fixed, bounds, static guard)
- [x] Phase 1 — mandate written
- [x] Phase 2 — analysis + **first baseline measured** (this file)
- [ ] Phase 3 — triage all 210 failures into the 4 categories above
- [ ] Phase 4 — safety fixes (compositor inside the bound) **before** any `-j8` run
- [ ] Phase 5 — fill gaps G1–G8
- [ ] Phase 6 — full green run, report to owner
- [ ] Phase 7 — fix the product bugs found

## How to re-run the baseline

```bash
# sentinel (system-level net) — optional but recommended
FLOOR_MB=60000 nohup <scratchpad>/oom_sentinel.sh &

RUN_MEM_MAX_MB=2048 RUN_AS_MAX_MB=12288 RUN_TIMEOUT=900 \
  ./tests/gui/run_gui_tests.sh --fast -j4

cat build/gui-logs/summary.txt      # per-file pass/fail
cat build/gui-logs/failures.txt     # the FAIL! lines
```
