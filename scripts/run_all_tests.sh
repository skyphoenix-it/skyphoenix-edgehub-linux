#!/usr/bin/env bash
# run_all_tests.sh — run every test suite in the project and aggregate the result.
#
# Suites:
#   1. Rust core            : cd core && cargo test
#   2. QML GUI              : scripts/run_ui_tests.sh (offscreen qmltestrunner)
#   3. C++ (ctest)         : only if a build dir with tests already exists
#   4. QML behavior matrix : python3 scripts/qml_coverage.py
#   5. Runtime E2E battery : tests/runtime/run_*.sh — nine scenarios driving the
#                            REAL hub binary (focus goal bonus, w/h→size
#                            migration, org policy, update-check-off, secret
#                            refs, corrupt salvage, reset flags, live-push
#                            single-writer, page-name dedup). Each needs a hub
#                            binary and SKIPs (77) if none is built/installed.
#
# Exits non-zero if any suite fails. Prints a clear per-suite summary.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

# Names and outcomes kept in parallel arrays (bash 3.2 compatible).
names=()
results=()

run_suite() {
    local name="$1"; shift
    echo ""
    echo "==================================================================="
    echo "==> ${name}"
    echo "==================================================================="
    names+=("$name")
    if "$@"; then
        results+=("PASS")
        echo "--- ${name}: PASS"
    else
        results+=("FAIL")
        echo "--- ${name}: FAIL"
    fi
}

# 1. Rust core tests.
run_suite "Rust (cargo test)" bash -c 'cd "'"$PROJECT_DIR"'/core" && cargo test'

# 2. QML GUI tests.
run_suite "QML GUI (run_ui_tests.sh)" bash "$PROJECT_DIR/scripts/run_ui_tests.sh"

# 3. C++ ctest — only when a build tree with tests exists.
if [ -d "$PROJECT_DIR/build" ] && [ -f "$PROJECT_DIR/build/CTestTestfile.cmake" ]; then
    # The two smoke tests QSKIP unless the tree was configured with
    # -DXENEON_QA_HOOKS=ON, because XENEON_GRAB is compiled out otherwise. A
    # default build therefore reports 21/21 green having launched NEITHER real
    # binary. Silent skips are how a suite rots, so say it out loud.
    if ! grep -q '^XENEON_QA_HOOKS:BOOL=ON' "$PROJECT_DIR/build/CMakeCache.txt" 2>/dev/null; then
        echo ""
        echo "!! WARNING: build/ configured WITHOUT -DXENEON_QA_HOOKS=ON."
        echo "!! tst_smoke_hub and tst_smoke_manager will QSKIP — ctest will report"
        echo "!! green having never launched the real hub or manager binary."
        echo "!! Reconfigure: cmake -B build -DXENEON_BUILD_TESTS=ON -DXENEON_QA_HOOKS=ON"
        echo ""
        names+=("C++ smoke hooks (XENEON_QA_HOOKS)")
        if [ "${XENEON_ALLOW_SMOKE_SKIP:-0}" = "1" ]; then
            results+=("SKIP")
        else
            results+=("FAIL")
        fi
    else
        names+=("C++ smoke hooks (XENEON_QA_HOOKS)")
        results+=("PASS")
    fi
    run_suite "C++ (ctest)" ctest --test-dir "$PROJECT_DIR/build" --output-on-failure
else
    echo ""
    echo "==> C++ (ctest): SKIPPED (no build tree with tests; run cmake -B build -DXENEON_BUILD_TESTS=ON)"
    names+=("C++ (ctest)")
    results+=("SKIP")
fi

# 4. QML behavior-matrix coverage gate.
run_suite "QML behavior matrix (qml_coverage.py)" python3 "$PROJECT_DIR/scripts/qml_coverage.py"

# Static guard against the scene-graph walk bug that caused a system-wide OOM on
# 2026-07-19 (three independent copies; 18.8 GB and 20 GB RSS). Cheap and fast —
# keep it ahead of the heavy suites so a reintroduction fails in seconds.
run_suite "Tree-walk memory guard (check_tree_walks.py)" python3 "$PROJECT_DIR/scripts/check_tree_walks.py"

# 4b. Egress lint — raw XMLHttpRequest may only live in the NetHub gate.
run_suite "Egress lint (no raw XHR)" bash "$PROJECT_DIR/scripts/check_no_raw_xhr.sh"
run_suite "Live-test lint (no inert test_*_data)" bash "$PROJECT_DIR/scripts/check_live_tests.sh"
# The Manager is never tested inside a nested compositor — it is tested against
# a REAL hub in tests/hardware/. See the script header for why this is absolute.
run_suite "No Manager tests under a compositor" bash "$PROJECT_DIR/scripts/check_no_manager_compositor_tests.sh"
run_suite "Doc links (files + anchors)" bash "$PROJECT_DIR/scripts/check_doc_links.sh"
run_suite "UI links (no dead openUrlExternally)" bash "$PROJECT_DIR/scripts/check_ui_links.sh"

# 4c. Icon lint — every widget type needs a bundled, registered picker icon (the
#     QML suite can't see missing assets: it runs source-tree, with no qrc).
run_suite "Icon lint (widget types)" bash "$PROJECT_DIR/scripts/check_widget_icons.sh"

# 4d. AppImage update contract — the cross-file invariants of the zsync delta-update
#     path (artifact name ↔ binary appVersion ↔ zsync -u URL ↔ UpdateChecker's repo).
#     No single suite spans those four files, and every one of them was independently
#     broken while the rest of the tests stayed green.
run_suite "AppImage update contract" bash "$PROJECT_DIR/scripts/check_appimage_update_contract.sh"

# 5. Runtime E2E battery — drives the real hub binary through one scenario
#    script per guarantee (see tests/runtime/README.md). Exit 77 = SKIP (no
#    binary built or installed); anything else is PASS/FAIL as usual.
runtime_scenarios=(
    "focus goal bonus:run_focus_goal_bonus.sh"
    "01 w/h→size migration:run_01_wh_size_migration.sh"
    "02 org policy:run_02_org_policy.sh"
    "03 update check off:run_03_update_check_off.sh"
    "04 secret refs:run_04_secret_refs.sh"
    "05 corrupt salvage:run_05_corrupt_salvage.sh"
    "06 reset flags:run_06_reset_flags.sh"
    "07 live push single-writer:run_07_live_push_single_writer.sh"
    "08 page dedup roundtrip:run_08_page_dedup_roundtrip.sh"
)
for entry in "${runtime_scenarios[@]}"; do
    rt_name="${entry%%:*}"; rt_script="${entry#*:}"
    echo ""
    echo "==================================================================="
    echo "==> Runtime E2E ($rt_script)"
    echo "==================================================================="
    names+=("Runtime E2E ($rt_name)")
    # `if` guards against `set -e` aborting on a non-zero (fail/skip) exit.
    if bash "$PROJECT_DIR/tests/runtime/$rt_script"; then rt_rc=0; else rt_rc=$?; fi
    if [ "$rt_rc" -eq 0 ]; then
        results+=("PASS"); echo "--- Runtime E2E ($rt_name): PASS"
    elif [ "$rt_rc" -eq 77 ]; then
        results+=("SKIP"); echo "--- Runtime E2E ($rt_name): SKIPPED (no hub binary)"
    else
        results+=("FAIL"); echo "--- Runtime E2E ($rt_name): FAIL"
    fi
done

# 5b. Manager suites — the REAL Manager binary driven with REAL input against
#     the REAL hub over the control socket. These replaced the deleted
#     tests/gui Manager tests, which ran against a stubbed backend inside a
#     nested compositor and whose pixel assertions were provably false.
#
#     Desktop input is opt-in twice over (XENEON_HW_INPUT + _DESKTOP), because
#     the cursor moves on the owner's screen. Without both, this SKIPs loudly.
echo ""
echo "==================================================================="
echo "==> Manager (real binaries, real hub)"
echo "==================================================================="
names+=("Manager (real Manager + real hub)")
if bash "$PROJECT_DIR/scripts/run_manager_tests.sh"; then
    results+=("PASS")
else
    mgr_rc=$?
    if [ "$mgr_rc" -eq 77 ]; then
        results+=("SKIP")
        echo "--- Manager suites: SKIPPED (desktop input not opted in)"
    else
        results+=("FAIL")
    fi
fi

# 6. QML compositor suite (tests/gui) — real KWin, real input, real pixels, and
#    the ONLY aspect-ratio assertions in the repo. It was orphaned for months
#    AND could not fail (it exited 0 unconditionally; fixed 2026-07-20).
#
#    NON-BLOCKING for now: it carries ~210 known failures. A permanently-red
#    gate is how a suite gets ignored, which is the disease being treated here.
#    Phase 1 of docs/agent-memory/TEST-STRATEGY-v2.md drives it green; FLIP THIS
#    TO BLOCKING at the end of Phase 1 by removing the `|| true` and the
#    NONBLOCKING label.
if [ "${XENEON_SKIP_GUI_SUITE:-0}" = "1" ]; then
    echo ""; echo "==> QML compositor suite: SKIPPED (XENEON_SKIP_GUI_SUITE=1)"
    names+=("QML compositor (tests/gui) [NONBLOCKING]"); results+=("SKIP")
elif ! command -v kwin_wayland >/dev/null 2>&1; then
    echo ""; echo "==> QML compositor suite: SKIPPED (no kwin_wayland)"
    names+=("QML compositor (tests/gui) [NONBLOCKING]"); results+=("SKIP")
else
    echo ""
    echo "==================================================================="
    echo "==> QML compositor suite (tests/gui)  [NON-BLOCKING until Phase 1]"
    echo "==================================================================="
    names+=("QML compositor (tests/gui) [NONBLOCKING]")
    # -j8 deliberately: run_gui_tests.sh defaults to J=1, which its own header
    # says takes "hours"; -j8 brings the tier under half an hour. Each file gets
    # its OWN nested KWin, and run_bounded caps every slot at RUN_MEM_MAX_MB, so
    # the ceiling is bounded rather than trusting the kernel OOM killer.
    if bash "$PROJECT_DIR/tests/gui/run_gui_tests.sh" -j"${XENEON_GUI_JOBS:-8}"; then
        results+=("PASS")
    else
        # Recorded, not fatal — see the comment above.
        results+=("KNOWN-RED")
        echo "--- QML compositor suite: KNOWN-RED (not failing the run; Phase 1 owns this)"
    fi
fi

# --- Summary ---
echo ""
echo "==================================================================="
echo "  TEST SUMMARY"
echo "==================================================================="
fail=0
for i in "${!names[@]}"; do
    printf "  %-40s %s\n" "${names[$i]}" "${results[$i]}"
    [ "${results[$i]}" = "FAIL" ] && fail=1
done
echo "==================================================================="

if [ "$fail" -ne 0 ]; then
    echo "RESULT: FAILURE"
    exit 1
fi
echo "RESULT: SUCCESS"
