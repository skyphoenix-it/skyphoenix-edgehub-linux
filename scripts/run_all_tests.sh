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
    run_suite "C++ (ctest)" ctest --test-dir "$PROJECT_DIR/build" --output-on-failure
else
    echo ""
    echo "==> C++ (ctest): SKIPPED (no build tree with tests; run cmake -B build -DXENEON_BUILD_TESTS=ON)"
    names+=("C++ (ctest)")
    results+=("SKIP")
fi

# 4. QML behavior-matrix coverage gate.
run_suite "QML behavior matrix (qml_coverage.py)" python3 "$PROJECT_DIR/scripts/qml_coverage.py"

# 4b. Egress lint — raw XMLHttpRequest may only live in the NetHub gate.
run_suite "Egress lint (no raw XHR)" bash "$PROJECT_DIR/scripts/check_no_raw_xhr.sh"
run_suite "Live-test lint (no inert test_*_data)" bash "$PROJECT_DIR/scripts/check_live_tests.sh"
run_suite "Doc links (files + anchors)" bash "$PROJECT_DIR/scripts/check_doc_links.sh"

# 4c. Icon lint — every widget type needs a bundled, registered picker icon (the
#     QML suite can't see missing assets: it runs source-tree, with no qrc).
run_suite "Icon lint (widget types)" bash "$PROJECT_DIR/scripts/check_widget_icons.sh"

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
