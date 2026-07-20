# Session handoff — 2026-07-20, r236

Written so work can resume with no gaps after an IntelliJ/system restart.
Read this first, then `TEST-STRATEGY-v2.md`.

---

## 1. Where we are in one paragraph

Simon asked why the project keeps regressing on features that were fixed dozens
of versions ago. Four parallel audits established that this is **not a coverage
problem** — ~9,464 assertions across 176 test-bearing files already exist. They
regress anyway because a large fraction **never execute** and another fraction
**cannot fail**. Phase 0 (make the existing suite able to fail) is **COMPLETE**.
Phase 1 (drive `tests/gui/` green) is **STARTED**: the single biggest blocker —
widgets never rendering in any automated tier — is **FIXED**. 80 GUI failures
remain to triage.

## 2. Current verified numbers (r236)

| Tier | Result |
|---|---|
| Rust (cargo test) | PASS |
| C++ ctest (21 targets) | PASS |
| C++ smoke hooks (XENEON_QA_HOOKS) | PASS |
| QML behaviour matrix (>=95%) | PASS |
| Tree-walk OOM guard | PASS |
| 5 structural lints | PASS |
| AppImage update contract | PASS |
| Runtime E2E | 8/9 PASS (see 6.1 — the 1 failure was environmental) |
| QML offscreen (93 files) | 0 assertion failures; run FAILS on 54 teardown diagnostics (see 5.1) |
| QML compositor (20 files) | **pass=1450 fail=80** |

GUI failures by file: `mgr_theme_accent` 28 · `mgr_nav` 11 · `shell_wallpaper_presets`
11 · `shell_nav_edit` 10 · `w_media_data` 9 · `edgeclone_screens_dialogs` 8 ·
`mgr_bg_glass_images` 2 · `shell_orient_settings` 1.

**Do not compare 1450/80 against the older 1382/70 or the doc's 1356/210.** Those
were measured (a) with widgets not rendering and (b) with one file silently
failing to compile. The current numbers are the first honest baseline.

## 3. What was DONE this session

### Phase 0 — make the existing suite able to fail (COMPLETE)

- **0.1 CI now triggers on `v1.0-alpha`** (`ci.yml`). It was master-only on the
  stated precondition of ff-only lockstep; that was void — the branch was 86
  commits ahead and 31 of the last 62 fixes, 28 user-visible, had had zero CI
  runs. The comment now forbids restoring the narrow trigger without the lockstep.
- **0.2 `tests/gui/run_gui_tests.sh` can fail.** It ended in an `echo`, so it
  printed `RESULT: FAILURE` and **exited 0**. Also gained an anti-vacuity floor
  (0 files executed = failure).
- **0.3 GUI tier wired in** to `run_all_tests.sh` and a new `gui-test` CI job,
  both **NON-BLOCKING** with explicit "REMOVE AT END OF PHASE 1" markers.
- **0.4 QML runtime errors are now failures** — new
  `scripts/check_qml_diagnostics.sh`, wired into `run_ui_tests.sh`.
- **0.5 `XENEON_QA_HOOKS` silent skip** now fails `run_all_tests.sh` (override
  `XENEON_ALLOW_SMOKE_SKIP=1`). Without it the two C++ smoke tests QSKIP and
  ctest reports 21/21 having launched neither real binary.
- **0.6 Orphaned gates into CI**: tree-walk OOM guard, AppImage contract, and
  the 9-scenario runtime E2E battery. All three previously ran in no workflow.
- **0.7 `timeout-minutes`** on all six CI jobs (there were none).
- **`run_all_tests.sh` GUI tier now `-j8`** (override `XENEON_GUI_JOBS`); it was
  `J=1`, which the script's own header says takes "hours".

**Exit criterion PROVEN**, not asserted: reverting the em-dash fix produced
`FAIL!  : QuoteParse::test_emdash_separator` and exit 1; restoring returned
47/47 and a clean tree.

### The big unlock — widgets now render in tests (7b2d4b2)

`qml.qrc` aliases widget QML **flat** into the bundle
(`alias="qml/CpuWidget.qml"` -> `qml/widgets/CpuWidget.qml`). Under
`qmltestrunner` there is no bundle, so every `qrc:/qml/*.qml` resolved to
nothing and **every tile silently failed to load** — ~2,400 load failures in the
offscreen suite alone, failing nothing.

Consequence, measured: widgets were tested **only in isolation at a sizeClass
the test supplied by hand** (`tst_gui_w_sys_a.qml:103`), and the shell was
tested **with no widgets in it** (`tst_gui_shell_nav_edit.qml` says so:
"never widget pixels"). **Nothing rendered a widget inside the real shell at a
size the real layout computed** — which is exactly the seam the Manager/hub
`sizeClassFor` divergence lives in, and why it could only ever be found by eye.

Fixed in `WidgetCatalog.source()` and `main.qml`'s StackView pages using the
same bundle-vs-source-tree rule `Theme._fontsDir` already used. Widget-load
failures **~2,400 -> 0**.

### Product bugs fixed

| Commit | Bug |
|---|---|
| `c02c40f` | Hub Settings->Background picker **completely inert** — QML self-binding trap (`store: store` resolving to the component's own undefined property). Same trap `WidgetConfigPanel` documented. |
| `fe39292` | Dangling `store` ref left by that rename (the regex only matched `store.` with a dot). |
| `edf8109` | `FirstRunWizard.qml:159` bound `visible:` to a possibly-absent key ("Unable to assign [undefined] to bool"). |
| `7b2d4b2` | `FocusWidget` `Qt.callLater(_syncIdleDuration)` firing against a half-destroyed tile. Guarded with `Component.onDestruction`. |
| `a503c4f` | `update-local.sh` could build without installing, near-silently (see 6.2). |

### Test-integrity bugs fixed

- **`tst_main::test_bindStackItem_leaves_netHub_null_without_a_dashboard` passed
  for the wrong reason** — it asserted "no dashboard on the stack" while relying
  on the Dashboard being *unable to load*. Never exercised its branch. Now finds
  the StackView (`main.qml` gained `objectName: "mainStack"`) and empties it
  deliberately, with the precondition asserted.
- **Four tests pinned the literal `"qrc:/qml/CpuWidget.qml"`** — the harness, not
  the behaviour. Rewritten to assert the file they point at, keeping the exact
  qrc assertion on the bundled branch so no bite is lost.
- **`tst_gui_shell_wallpaper_presets.qml` had not COMPILED since `c02c40f`** —
  it still bound `store:` on a real `BackgroundPicker`. ~79 assertions were
  silently absent from every run and the totals moved so little nobody noticed.
  Now 68 pass / 11 fail.

## 4. What was WRONG and corrected (read this — it prevents repeats)

- **I claimed "the offscreen tier is clean"** from a stderr scan showing zero.
  `qmltestrunner` reports QML errors as **`QWARN` on STDOUT**. The gate was
  itself the vacuous check it exists to catch. Re-measured: 2,631 QWARN lines.
  **Always prove a detector can emit a 1 before believing its 0.**
- **I nearly reported "the wheel-scroll regression (#5) is back."** It is not.
  `TODO-gui-testsuite.md:32` records `tst_gui_mgr_nav | 73 | 11` — identical to
  today. Those 11 have failed since the suite was written; the wheel pins for
  that 3x-recurring bug have **never once passed**.
- **I hypothesised the Manager window received no input.** Disproved by the log:
  `test_m7_stop_click_calls_backend()` passes while `m6` fails, so clicks land.
  It is specific to `mouseWheel`, in the only file that uses it.
- **I caused a 75-failure regression** with the qrc fix (see 5.2) and had to fix it.
- **The pinning tally (30 PINNED / 11 WEAK / 19 UNPINNED) came from READING
  diffs, not reverting.** Verification already moved two verdicts. Treat as
  directional. **Revert-and-run before acting on any individual line.**

## 5. OPEN ITEMS — what needs to be done next

### 5.1 DECISION NEEDED: 54 teardown diagnostics

52 come from `tst_gen_notes`' two *deliberate destroy* tests, where the harness'
`theme` alias unwinds while `WidgetChrome` bindings re-evaluate. The new gate
correctly fails the offscreen run on them. **Deliberately NOT masked** — silent
filtering is how the suite got into this state.

Options: (a) guard the binding sites in `WidgetChrome` (dozens of edits, zero
user-visible benefit), or (b) a narrow, documented allowlist with a review date.

### 5.2 Phase 1 remaining — triage the 80 GUI failures

Split into real bugs / stale tests / harness limits. Known so far:

- `mgr_nav` 11 — all `mouseWheel`; **undetermined** whether harness limitation
  under `--virtual` or real defect. **Decisive experiment:** run that one file
  with `--visible` (puts a window on Simon's screen for a few minutes — he must
  green-light it).
- `shell_wallpaper_presets` 11 — newly running after the compile fix; never triaged.
- `mgr_theme_accent` 28 — the largest block, untouched.

### 5.3 Add a per-file "did this compile?" floor

`tst_gui_shell_wallpaper_presets` contributed 0 passes for many revisions and
nothing noticed. Same class as the orphaned runner and the always-exit-0 script.

### 5.4 Phase 2 (not started) — see TEST-STRATEGY-v2.md

2.1 delete the duplicated `EdgeClone.sizeClassFor` (**the actual WYSIWYG bug** —
`Dashboard.sizeClassFor(size, landscape)` vs `EdgeClone.sizeClassFor(size)`
hardcoding portrait; `halfUnits` swaps w/h on that flag, so landscape gives the
hub `wide` and the Manager `tall`) · 2.2 golden images/SSIM · 2.3 animation as
motion, not a config flag · 2.4 capacity re-validation in `applyExternal` ·
2.5 screen-composed geometry invariants · 2.6 real input at real call sites ·
2.7 extract `isEdgeScreen()` into a linkable `display_match.h`.

**Phase 0 only closed Category C** (pins that work but never run). Category A
(absent pins — Manager window placement is `static` in `main.cpp`, not linkable
from any test) and Category B (pins that cannot observe the failure — add-page
snap-back is pinned yet regressed twice) need 2.7 and the compositor tier.

### 5.5 Simon's three standing decisions (still open)

1. **Pro gating is bypassable.** Gated features are exactly 9 themes, enforced
   at two QML call sites (`SettingsPanel.qml:203`, `Manager.qml:406`). Writing
   `themeMode: "synthwave"` into `ui_state` bypasses both.
2. **Seven features ship unreachable** — no UI for `fontChoice`, `textScale`,
   `reduceMotionPreference`, `enableUserWidgets`, `netOffline`, 7 accent presets,
   `applyPreset()`. Three are accessibility features, working and tested, with no
   way to turn them on.
3. **CI:** keep triggering on both, or merge alpha into master and restore lockstep.

### 5.6 Also outstanding (pre-existing)

Two unverified marketing claims (`~3.5% CPU` in `LAUNCH_COPY.md`; README says 15
presets, catalog has 19 — `PresetPicker.qml`'s header also says 15). Release
still needs an AppImage + `.zsync` attached. Secret scanning / push protection
not enabled. 202 MB history blob.

## 6. Gotchas that will bite on resume

### 6.1 Installing while tests run kills the tests

`update-local.sh:105` runs `pkill -TERM -x xeneon-edge-hub`. `rt_common.sh:25`
launches the test hub as `build/xeneon-edge-hub` — process name **exactly**
`xeneon-edge-hub`. Installing at 02:54:35 SIGTERM'd the runtime tier's own hub
and failed scenario 06, which passes standalone. **Do not install while the
battery runs.** Worth fixing properly.

### 6.2 update-local.sh needs an interactive password

`sudo pacman -U` prompts; unanswered under `set -euo pipefail` it aborts *after*
the build, *before* the install — leaving a fresh package and an untouched
system. Now pre-flights the credential and asserts the install landed. **Run it
from a real terminal (or `! ./scripts/update-local.sh`).**

### 6.3 The GUI suite is invisible by design

`kwin_wayland --virtual` renders to an off-screen framebuffer. Seeing nothing on
the Edge does **not** mean it is hung. Check `ls -lt build/gui-logs/*.log`.

### 6.4 Don't edit QML while a suite runs

The runners read the source tree live.

### 6.5 Don't pipe long runs through `tail`

It buffers until completion; the runtime-06 failure detail was lost that way.

### 6.6 Memory

`-j8` x 2048 MB cap = ~16 GB worst case; box has ~187 GB free. `run_bounded.sh`
uses `ulimit -v` + an RSS watchdog — **never** the kernel OOM killer.

## 7. Conversation trail (recent turns, condensed)

1. Finished the `BackgroundPicker` inert-picker fix (`c02c40f`), then found and
   fixed my own dangling `store` ref (`fe39292`).
2. Simon: *"Look configsection has a different layout than Screens... widgets are
   not WYSIWYG on the Manager... hub shows more infos, ratio is different."*
   -> Root-caused to `EdgeClone.qml:290` hardcoding portrait. **Still unfixed —
   this is Phase 2.1.** The Look-vs-Screens layout asymmetry (`Manager.qml:811`
   GridLayout vs `:1357` plain ColumnLayout) is also **still unfixed**.
3. Simon: *"run a full testsuite... we are regularly regressing... plan a huge
   test strategy... get back to me with a coherent plan."* -> 4 audits ->
   `TEST-STRATEGY-v2.md`.
4. Simon: *"Start Phase 0, enable CI on v1.0-alpha."* -> Phase 0 complete.
5. Simon: *"non-blocking is fine, continue with the rest of phase 0."* -> done.
6. Simon: *"fix the qrc resolution so widgets render in tests."* -> `7b2d4b2`.
7. Simon: *"Rerun the GUI Suite. I am on 234... Check everything now."* -> full
   battery; found installed binaries were r229, not 234.
8. Simon: *"I ran the update-script, but it didn't update."* -> diagnosed the
   sudo abort; fixed the script (`a503c4f`).
9. Simon: *"now 234 is running. Now you can run the GUI Testsuite."*
10. Simon: *"not sure if anything is running... maybe kill it."* -> it was
    running fine (`--virtual`), finished seconds later.
11. Found and fixed my duplicate-Dashboard regression and the file that had not
    compiled since `c02c40f` (`a3f94ca`). Final: **1450/80**.

## 8. Commits this session

```
a3f94ca fix(tests): one Dashboard per shell test; restore a file my rename had disabled
a503c4f fix(dev): update-local.sh could build without installing, near-silently
7b2d4b2 fix(tests): resolve widget QML from the source tree so widgets actually render
94209b7 test(phase0): wire the orphaned gates into CI; loud QA_HOOKS skip
edf8109 test(phase0): make the existing suite able to fail
25e4b0b docs(testing): test strategy v2 — regression root-cause analysis + plan
fe39292 fix(hub): dangling `store` ref left by the BackgroundPicker rename
c02c40f fix(hub): on-panel Background picker was inert (QML self-binding trap)
```

## 9. First things to do on resume

1. Read this file, then `TEST-STRATEGY-v2.md` (incl. its CORRECTION block).
2. Get Simon's call on 5.1 (teardown diagnostics) and 5.5 (the three decisions).
3. Ask about the `--visible` experiment for the wheel tests (5.2).
4. Continue Phase 1 triage: `mgr_theme_accent` (28) is the largest block.
5. Phase 2.1 is the fix Simon actually reported and is still outstanding.
