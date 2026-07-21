# MANDATE - Full GUI test suite for Manager + Hub (owner request, 2026-07-19)

> **READ THIS FIRST IF YOU ARE AN AGENT RESUMING AFTER A CRASH.**
> This is the standing instruction from the repo owner (Simon). It survives
> context loss. Work the phases in order. Update the checkboxes as you go.
> Companion files: [`TODO-gui-testsuite.md`](TODO-gui-testsuite.md) (the plan),
> [`companion-and-testing.md`](companion-and-testing.md) (existing harnesses).

## Why this file exists

On 2026-07-19 an unbounded QML test drove `qmltestrunner` to 18.8 GB RSS. The
kernel fired a **system-wide OOM** and killed the owner's IntelliJ. The owner's
words: *"I NEVER want to have a 'OOM' Message and error and potential crashes of
Intellij or my entire system EVER again."* If you crash the machine again, the
work restarts from this file.

## The request, in the owner's terms

1. **In-depth analysis** of what is still broken in Manager and Hub - including
   going over them **visually**, not just by reading code.
2. Use **many perspectives**: tester, automation engineer, analyst, UI/UX, end
   user, rubber-duck, security engineer, and **especially architects who
   understand memory leaks**, so we do not crash the system again.
3. **Plan a complete test suite** - heavy focus on **real GUI tests** driving the
   actual Manager and Hub. Not headless-only, not unit-only. A smaller set of
   unit/headless tests is still included, but GUI is the centre of gravity.
4. **Every single feature** tested, **and integration-tested across Manager↔Hub**.
5. **Orientation flip must be simulated** - force horizontal and vertical display
   and back - and everything checked for coherence: things working together,
   fitting together, no layout breakage in either orientation.
6. **Implement** the suite, then **run it** against the current Manager and Hub on
   the owner's machine.
7. **Report results**, then fix the visual and functional bugs found.

## Non-negotiable safety rules

- **No kernel OOM. Ever.** Bound every child process in BOTH time and memory.
- Use `scripts/lib/run_bounded.sh` (`ulimit -v` + process-tree RSS watchdog).
- **Never** use cgroup caps / `systemd-run -p MemoryMax=`: the kernel then picks
  the victim and the desktop raises a "system is low on memory" notification.
  The owner explicitly rejected this even when it was contained.
- Check `oom-kill:constraint=` in `journalctl` - `CONSTRAINT_MEMCG` is
  cgroup-local, **`global_oom` is the dangerous one**. Target: 0 global_oom.
- Kill only processes belonging to this repo. Never the IDE, never unrelated work.
- **Never run `tests/hardware/edge_hw_test.py`** on the owner's machine. With a
  live hub running it finds the *real* control socket, rewrites
  `~/.config/xeneon-edge-hub/config.toml`, warps the cursor, and sends `shutdown`.
- `tests/hardware/edge_e2e.py` takes ~72 **full-desktop** screenshots across all
  three monitors. Ask before running it - that is the owner's screen content.
- Do not commit, push, merge, release, or delete recovery data without asking.

## The bug class that caused the crash - do not reintroduce

A QML node is reachable through several overlapping child axes: `children`,
`data`, `contentItem`, `contentData`, `visibleChildren`, `resources`. A recursive
walk descending **two or more** of these **without a visited-set** re-walks each
subtree once per path - **exponential in depth** (1,701 real nodes →
>2,000,000 visits). Found in three files, all now fixed. Descending exactly one
axis is a true tree and is safe.

Guard: `scripts/check_tree_walks.py`, wired into `scripts/run_all_tests.sh`.
Regression test: `tests/gui/tst_gui_util_walk.qml`.

## Phases - update as you go

- [x] **Phase 0 - Recovery + hardening.** 3 leaks fixed, bounds in place, static
      guard added and proven to catch all 3. Suites green: UI 88 files/0 fail
      (peak 119 MB, was 7,165 MB), ctest 21/21, runtime E2E 9/9.
- [x] **Phase 1 - Write this mandate.** (this file)
- [ ] **Phase 2 - Multi-perspective analysis + plan.** Save to
      `TODO-gui-testsuite.md` before implementing anything.
- [ ] **Phase 3 - Implement the suite.** Save progress to the TODO as you go.
- [ ] **Phase 4 - Run it, bounded.** Report results to the owner.
- [ ] **Phase 5 - Fix the bugs found.** Only after reporting.

## State at the time of writing

- Branch `v1.0-alpha` @ `98cf6e4`, 46 ahead of origin. **Nothing committed** -
  all Phase 0 work is uncommitted in the working tree.
- Existing harnesses: `tests/ui/` (88 offscreen QML files), `tests/gui/`
  (untracked, ~20 real-compositor files, never had a green baseline),
  `tests/runtime/` (9 headless E2E), `tests/cpp/` (21 ctest), `tests/hardware/`
  (never run here).
- Release blockers are decisions, not code: D1 default theme, D2 default font,
  D3 legal pass on distro theme naming, D4 keygen + store product. Plus the
  AppImage zsync path, which is an RC exit criterion and has never worked.
