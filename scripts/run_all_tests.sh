#!/usr/bin/env bash
# run_all_tests.sh — run every test suite in the project and aggregate the result.
#
# Suites:
#   1. Rust core            : cd core && cargo test
#   2. QML GUI              : scripts/run_ui_tests.sh (offscreen qmltestrunner)
#   3. C++ (ctest)         : only if a build dir with tests already exists
#   4. QML behavior matrix : python3 scripts/qml_coverage.py
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
