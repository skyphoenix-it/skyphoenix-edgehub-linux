# Real-hardware validation — 2026-07-21

## Outcome

The Hub, the real Xeneon Edge, the real Manager, and the Hub→Manager integration
path were exercised on the physical KDE Wayland desktop. Product rendering,
IPC, long-running stability, display lifecycle, reconnect behavior, and
Manager reflection passed after the fixes below.

After the owner explicitly approved completion, the noisy G502 was temporarily
disabled at KWin only for the controlled injection windows. The keyboard and
physical Edge touchscreen remained live owner-activity abort sources, all input
remained geometrically confined, and the G502 was restored after each run. This
closed every automatable real-input suite on the current KDE Wayland session.

## Scope and safety record

- Host: KDE Wayland (`wayland-0`), three connected outputs.
- Physical target: Corsair Xeneon Edge on `DP-3`; restored baseline is
  `720x2560`, position `5120,2880`, rotation `8` (right), scale `1`, priority `3`.
- Touch device: `wch.cn TouchScreen` (`27c0:0859`), mapped by KWin to `DP-3`.
- Repository start: `v1.0-alpha` at
  `684cddb073d31c26aa92e4ef7bb998b8ecea9f03`, with substantial pre-existing
  tracked and untracked work.
- Recovery snapshot created before source edits or app launches:
  `/home/simon/IdeaProjects/.codex-backups/XeneonEdge_Linux/20260721T152012Z`.
- Continuation snapshot created before the approved input completion pass:
  `/home/simon/IdeaProjects/.codex-backups/XeneonEdge_Linux/20260721T163608Z`.
- Snapshot contents: all Git refs, binary-safe tracked/staged patches, untracked
  source/test files (generated `build-cov-agent/` excluded), live Hub config,
  Git status, display inventory, checksums, and command logs.
- Hardware evidence, including the initial mixed-DPI false failure and corrected
  pass, is archived under the snapshot's `hardware-evidence/` directory.
- The live Hub config's SHA-256 stayed unchanged:
  `3001a5823ac73ef55626983d4200899801a33d5481d9b90a575c4f0d7ca1ba76`.
- No commit, stash, reset, cleanup of user files, package install, release, power
  operation, or suspend operation was performed.
- Every long-running child used `scripts/lib/run_bounded.sh` with explicit wall,
  process-tree RSS, and per-process address-space ceilings. No OOM event occurred.
- Synthetic input remained behind output/window confinement, render and landing
  proofs, a separate desktop opt-in, and the compositor owner-activity kill switch.

## Findings and fixes

### F-01 — Release build blocked by an invalid hermetic-test API call

- Status: fixed and verified.
- Reproduction: `cmake --build build`.
- Symptom: `tests/cpp/tst_network_access_policy.cpp` called nonexistent
  `requireHermeticTestEnvironment()`.
- Cause: the test included `hermetic.h` but did not install its required
  file-scope gate.
- Fix: use `XENEON_REQUIRE_HERMETIC_ENV()` and remove the invalid test slot.
- Verification: final Release build passed; C++ QtTest passed 22/22.

### F-02 — Release build blocked by an invalid QtTest assertion

- Status: fixed and verified.
- Symptom: `tests/cpp/tst_mpris_state.cpp` passed three arguments to the
  two-argument `QCOMPARE` macro.
- Fix: use `QVERIFY2(bridge.artUrl().isEmpty(), message)`, preserving the
  assertion and diagnostic.
- Verification: final Release build passed; C++ QtTest passed 22/22.

### F-03 — Valid local QML URL discarded by the wallpaper security filter

- Status: fixed and verified.
- Reproduction: `tst_dashboard.qml::test_wallpaper_source_is_local_only`.
- Symptom: remote/data wallpaper URLs were correctly rejected, but a valid local
  `Qt.url` also resolved to an empty source.
- Cause: `Dashboard.wallpaperSource` tested `.length` before converting a QML URL
  object to a string.
- Fix: reject null/undefined, stringify, then test emptiness and apply the
  local/qrc allowlist.
- Verification: targeted test passed and the full QML rerun passed 93/93 files.

### F-04 — Manager offline-preview test inspected unstable object ownership

- Status: fixed and verified.
- Reproduction: `tst_manager.qml::test_config_preview_is_offline_by_construction`.
- Symptom: the test could not reliably find the preview/geocode `NetHub` objects
  and could select the duplicate Weather tile in the main device preview.
- Cause: non-visual `QtObject` ownership and Popup visual reparenting are not a
  stable inspection API.
- Fix: expose the exact `previewNetHub`, `geocodeNetHub`, and read-only
  `previewItem`; assert the injected gate, allowlist, offline flag, and request
  counters directly.
- Verification: targeted test passed and the full QML rerun passed 93/93 files.

### F-05 — Physical mouse sensor churn blocks the owner-idle safety gate

- Status: isolated to the test environment; safety behavior verified; approved
  workaround completed and fully restored.
- Full-run observation: the real Edge window render proof passed, `VTouch` was
  readback-bound to `DP-3`, and both `rot270` IPC landing probes passed. The guard
  then saw an unattributed compositor resume 1.094 seconds after the final
  synthetic event and stopped all further injection.
- Focused rerun: KDE could not provide three continuous idle seconds within the
  full 90-second gate, so no virtual input device was created.
- Isolation probes (all devices restored afterward):
  - normal desktop: 22 idle/resume cycles in 15 seconds;
  - OpenLinkHub virtual keyboard/mice disabled: churn continued;
  - both Edge touchscreen interfaces disabled: churn continued;
  - only Logitech G502 `event5` disabled: KDE became continuously idle for about
    ten seconds.
- Initial decision: do not increase the attribution blind window or lower the
  three-second gate. After explicit owner approval, disable only KWin's G502 input
  device during controlled runs, leaving the keyboard and Edge touchscreen as
  live abort sources. A shell trap restored the mouse on success, failure,
  timeout, or termination; readback confirmed it enabled after every suite.
- Completion verification: all five real Manager suites passed 53/53 and the
  full Edge E2E passed 269/269, including 54 touch swipes during the 1,200-second
  soak. No kill-switch abort occurred.

### F-06 — Hub→Manager reflection suite injected a redundant desktop click

- Status: fixed and verified.
- Cause: the real Manager already starts on Screens, but the reflection suite
  created a virtual pointer solely to click that selected tab. This added risk
  and made non-input reflection depend on the noisy mouse's idle state.
- Fix: replace the click with a real-desktop screenshot proof that the Manager is
  frontmost in its logged window rectangle and that Screens is selected. Keep
  screen-count, theme, portrait, landscape, auto-orientation, and Hub-liveness
  assertions unchanged.
- Contract fix: input lifecycle checks now enumerate the four actual input
  drivers and separately assert that the reflection driver remains input-free.
- Verification: real Hub + real Manager reflection passed 8/8; hardware contract
  tests passed 9/9.

### F-07 — Mixed-DPI screenshot crops produced false lifecycle failures

- Status: fixed and verified.
- Reproduction: the first real display-lifecycle pass at 125% scale.
- Symptom: KScreen correctly reported `2048x576`, while the first probe claimed
  no dark/light render change at 125% and after the primary-role swap.
- Cause: on this mixed-DPI Wayland layout, Spectacle emitted a
  `14336x6912` compositor framebuffer for a `7168x3456` logical canvas. Cropping
  it with unscaled KScreen coordinates sampled the wrong output.
- Fix: the new separately gated lifecycle test derives X/Y framebuffer-to-logical
  scale from each grab before cropping. It always restores every output's saved
  enabled state, mode, position, rotation, scale, and priority in `finally`.
- Verification: corrected real rerun passed 15/15 attached-target checks plus 3/3
  missing-target checks. The fixed 125% crop measured a dark/light distance of
  about 349, confirming that the Hub had rendered correctly.

### F-08 — Manager hardware test used a soon-to-be-removed Pillow API

- Status: fixed and verified.
- Observation: the approved Manager input run emitted a deprecation warning for
  `Image.getdata()`, which Pillow 14 removes in 2027.
- Fix: prefer `Image.get_flattened_data()` and retain a fallback only for older
  distro Pillow versions.
- Verification: the real Manager tab/liveness suite reran 11/11 with no warning;
  the G502 was restored afterward.

## Verification ledger

### Automated and mocked/offscreen

- Final Release build: PASS.
- Rust: PASS — 242 tests; clippy on all targets with warnings denied; fmt check.
- C++ QtTest: PASS — 22/22 against temporary `XDG_CONFIG_HOME`.
- QML offscreen suite: PASS — 93/93 files after F-03/F-04.
- Hardware safety tests: PASS — 23/23.
- Hardware E2E contract tests: PASS — 9/9 after F-06.
- Python compile checks: PASS for the modified/new hardware drivers.
- These checks are automated or mocked/offscreen and are not counted as physical
  interaction evidence.

### Real Xeneon Edge, Hub, Manager, and integration

- Full real Edge E2E approved rerun: PASS 269/269 with no skips.
- Physical widget lifecycle: PASS for all 30 catalog types
  (add/render/log scan/resize/remove).
- Physical theming: PASS for all 29 themes and 11 background styles, plus accent,
  glass, and glow changes.
- Real IPC: PASS for malformed/partial/oversized input survival; p50 `0.02 ms`,
  p99 `0.11 ms` over 200 requests; 20/20 concurrent replies.
- Real 1,200-second approved soak: PASS — 2,169 mixed cycles, Hub alive, 54
  successful touch swipes under load, no abort, no OOM. Sampled Hub RSS stayed
  approximately 627–630 MiB with 35–37 threads and no upward leak trend.
- Real Manager chrome grabs: PASS for dark, light, and default states with no
  render errors.
- Real Hub→Manager reflection: PASS 8/8 — page chips, theme recolor, portrait,
  landscape, auto-orientation, and final Hub liveness.
- Real Manager input/integration runner: PASS 53/53 across all five suites:
  tab navigation/liveness 11/11; 14-widget capacity spill 20/20; page mirror 8/8;
  Hub→Manager reflection 8/8; drag reorder 6/6.
- Real KDE Wayland display lifecycle: PASS 18/18 — initial placement, restart,
  native landscape, 125% fractional scaling, Edge-as-primary, exact portrait
  restore, logical target disable, same-connector re-enable/migration, and
  configured-target-missing startup without primary-output hijack.
- Touch targeting evidence: `VTouch` mapped to `DP-3`; two independent controls
  accepted the measured `rot270` landing transform before F-05 stopped injection.

## Explicitly untested or incomplete

- KDE X11, GNOME Wayland, and GNOME X11; this host session is KDE Wayland only.
- Physical finger interaction on the touchscreen.
- Physical cable reconnection on a different GPU port. Same-connector logical
  disable/re-enable passed, but is not represented as a cable move.
- Physical monitor power-button cycle.
- Suspend/resume; suspending the owner's PC was not assumed from the test request.
- Physical rotation/orientation-sensor change; software portrait/landscape and
  Hub/Manager effective-orientation reflection passed.

## Files changed by this validation session

- `tests/cpp/tst_network_access_policy.cpp` — corrected hermetic test gate.
- `tests/cpp/tst_mpris_state.cpp` — corrected QtTest assertion form.
- `ui/qml/Dashboard.qml` — stringify QML URL before local-source validation.
- `manager/qml/WidgetConfigDialog.qml` — explicit, inspectable network gates and
  preview item surface.
- `tests/ui/tst_manager.qml` — stable offline-preview assertions.
- `tests/hardware/manager_reflection_test.py` — input-free real reflection proof.
- `tests/hardware/manager_gui_test.py` — Pillow 14-compatible pixel inspection.
- `tests/hardware/test_e2e_contract.py` — separate input and input-free contracts.
- `tests/hardware/display_lifecycle_test.py` — gated real lifecycle matrix with
  exact baseline restoration and mixed-DPI-aware render proofs.
- `tests/hardware/README.md` — documented the disruptive gate, scope, isolation,
  and exact restore behavior of the lifecycle matrix.
- `docs/testing/hardware-validation-2026-07-21.md` — this record.

These files already lived in a heavily dirty worktree in several cases; unrelated
pre-existing edits were preserved. No attempt was made to reset, reformat, or
claim unrelated changes.

## Activity log

1. Captured the recovery snapshot before source edits or app launches.
2. Inventoried Git, config, display, USB, input, runtime, and process state.
3. Ran the bounded Release build, recorded F-01/F-02, fixed, and rebuilt.
4. Ran the 93-file QML baseline, recorded F-03/F-04, fixed targeted tests, then
   completed a green 93-file rerun.
5. Completed Rust, C++, QML, and hardware safety/contract baselines.
6. Ran the full 23.3-minute real Edge E2E and 1,200-second soak; recorded F-05.
7. Ran a fresh focused touch rerun and four read-only/reversible idle probes,
   isolating the G502 event stream; restored every input device.
8. Removed redundant input from Hub→Manager reflection and completed the real
   8/8 reflection run.
9. Added the gated real display-lifecycle matrix, preserved its first failing
   evidence, fixed F-07, and completed the corrected 18/18 run.
10. Archived hardware frames/logs, restored the exact KScreen baseline, and
    verified the live Hub config checksum was unchanged.
11. Ran the final Release build, Python compile checks, 23 safety tests, and the
    corrected 9-test hardware contract suite.
12. Captured a second recovery checkpoint before the owner-approved completion.
13. Temporarily disabled only the noisy G502 in KWin, retained keyboard/touch
    abort sources, and passed all five real Manager suites (53/53); restored the
    mouse and archived every frame.
14. Repeated the controlled G502 isolation for the full 23.3-minute Edge E2E;
    passed 269/269, including 54 touch swipes in 2,169 mixed soak cycles.
15. Recorded F-08 from the Manager run, migrated to Pillow's replacement API,
    and reran the real Manager tab suite 11/11 without the warning.
16. Reconfirmed all input devices enabled, no test processes/devices, unchanged
    live config, exact display baseline, and no kernel OOM record.
