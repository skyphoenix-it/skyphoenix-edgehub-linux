#!/usr/bin/env bash
# coverage.sh — measure and gate test coverage across all layers.
#
#   Rust : cargo llvm-cov (LLVM source-based line coverage), gate >= 95%
#   C++  : gcovr over build/  -> coverage/cpp-lcov.info,        gate >= 95%
#   merge: Rust + C++ lcov    -> coverage/merged-lcov.info
#   QML  : scripts/qml_coverage.py (behavior matrix, reported; own gate)
#
# Skips a layer gracefully (with a clear message) when its tooling or build
# artifacts are absent, but still fails if a layer that COULD run is below gate.
# Final line: "Rust: X% | C++: Y% | merged: Z% | QML behaviors: N%".
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

COVERAGE_DIR="$PROJECT_DIR/coverage"
mkdir -p "$COVERAGE_DIR"

GATE=95

RUST_PCT="n/a"
CPP_PCT="n/a"
MERGED_PCT="n/a"
QML_PCT="n/a"
fail=0

# gcovr may live in ~/.local/bin rather than on PATH.
GCOVR=""
if command -v gcovr >/dev/null 2>&1; then
    GCOVR="gcovr"
elif [ -x "$HOME/.local/bin/gcovr" ]; then
    GCOVR="$HOME/.local/bin/gcovr"
fi

pct_ge_gate() {
    # pct_ge_gate <pct>  -> 0 if pct >= GATE else 1
    python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)" "$1" "$GATE"
}

# ---------------------------------------------------------------- Rust --------
echo "==> Rust coverage (cargo llvm-cov)"
if command -v cargo-llvm-cov >/dev/null 2>&1; then
    (
        cd "$PROJECT_DIR/core"
        cargo llvm-cov --lib --lcov --output-path "$COVERAGE_DIR/rust-lcov.info"
        cargo llvm-cov --lib --json --summary-only --output-path "$COVERAGE_DIR/rust-summary.json"
    )
    if [ -f "$COVERAGE_DIR/rust-summary.json" ]; then
        RUST_PCT="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("%.2f" % d["data"][0]["totals"]["lines"]["percent"])' "$COVERAGE_DIR/rust-summary.json")"
        echo "    Rust line coverage: ${RUST_PCT}%"
        if ! pct_ge_gate "$RUST_PCT"; then
            echo "    FAIL: Rust ${RUST_PCT}% < ${GATE}%"
            fail=1
        fi
    else
        echo "    WARN: rust summary not produced"
        fail=1
    fi
else
    echo "    SKIP: cargo-llvm-cov not installed (cargo install cargo-llvm-cov)"
fi

# ---------------------------------------------------------------- C++ ---------
echo "==> C++ coverage (gcovr)"
HAVE_GCNO=0
if [ -d "$PROJECT_DIR/build" ] && find "$PROJECT_DIR/build" -name '*.gcno' -print -quit 2>/dev/null | grep -q .; then
    HAVE_GCNO=1
fi
if [ -z "$GCOVR" ]; then
    echo "    SKIP: gcovr not found (pip install --user gcovr; also checked ~/.local/bin)"
elif [ "$HAVE_GCNO" -eq 0 ]; then
    echo "    SKIP: no coverage build (cmake -B build -DXENEON_BUILD_TESTS=ON -DXENEON_COVERAGE=ON && cmake --build build && ctest --test-dir build)"
else
    "$GCOVR" --root "$PROJECT_DIR" \
        --filter 'app/src/' --filter 'manager/src/' \
        --exclude '.*main\.cpp' \
        --lcov "$COVERAGE_DIR/cpp-lcov.info" \
        "$PROJECT_DIR/build" || echo "    WARN: gcovr lcov export reported an error"
    CPP_PCT="$("$GCOVR" --root "$PROJECT_DIR" \
        --filter 'app/src/' --filter 'manager/src/' \
        --exclude '.*main\.cpp' \
        --json-summary "$PROJECT_DIR/build" 2>/dev/null \
        | python3 -c 'import json,sys; print("%.2f" % json.load(sys.stdin)["line_percent"])' 2>/dev/null || echo "n/a")"
    echo "    C++ line coverage: ${CPP_PCT}%"
    if [ "$CPP_PCT" != "n/a" ] && ! pct_ge_gate "$CPP_PCT"; then
        echo "    FAIL: C++ ${CPP_PCT}% < ${GATE}%"
        fail=1
    fi
fi

# --------------------------------------------------------------- merge --------
echo "==> Merging lcov reports"
MERGE_INPUTS=()
[ -f "$COVERAGE_DIR/rust-lcov.info" ] && MERGE_INPUTS+=("$COVERAGE_DIR/rust-lcov.info")
[ -f "$COVERAGE_DIR/cpp-lcov.info" ] && MERGE_INPUTS+=("$COVERAGE_DIR/cpp-lcov.info")
if [ "${#MERGE_INPUTS[@]}" -eq 0 ]; then
    echo "    SKIP: no lcov inputs to merge"
else
    if command -v lcov >/dev/null 2>&1; then
        args=()
        for f in "${MERGE_INPUTS[@]}"; do args+=(--add-tracefile "$f"); done
        lcov "${args[@]}" --output-file "$COVERAGE_DIR/merged-lcov.info" >/dev/null 2>&1 \
            && echo "    merged -> coverage/merged-lcov.info" \
            || { cat "${MERGE_INPUTS[@]}" > "$COVERAGE_DIR/merged-lcov.info"; echo "    merged (concat fallback) -> coverage/merged-lcov.info"; }
    else
        # lcov absent: concatenating tracefiles is a valid combined lcov report.
        cat "${MERGE_INPUTS[@]}" > "$COVERAGE_DIR/merged-lcov.info"
        echo "    merged (concat, lcov not installed) -> coverage/merged-lcov.info"
    fi
    # Compute merged line % from the tracefile (DA lines: hit if count > 0).
    MERGED_PCT="$(python3 - "$COVERAGE_DIR/merged-lcov.info" <<'PY'
import sys
total = hit = 0
for line in open(sys.argv[1]):
    if line.startswith("DA:"):
        parts = line[3:].strip().split(",")
        if len(parts) >= 2:
            total += 1
            if int(parts[1]) > 0:
                hit += 1
print("%.2f" % (100.0 * hit / total if total else 100.0))
PY
)"
    echo "    merged line coverage: ${MERGED_PCT}%"
    if ! pct_ge_gate "$MERGED_PCT"; then
        echo "    FAIL: merged ${MERGED_PCT}% < ${GATE}%"
        fail=1
    fi
fi

# ---------------------------------------------------------------- QML ---------
echo "==> QML behavior matrix (qml_coverage.py)"
QML_OUT="$(python3 "$PROJECT_DIR/scripts/qml_coverage.py")"
QML_STATUS=$?
echo "$QML_OUT"
QML_PCT="$(printf '%s\n' "$QML_OUT" | sed -nE 's/.*ratio[^0-9]*([0-9]+(\.[0-9]+)?)%.*/\1/p' | head -1)"
[ -z "$QML_PCT" ] && QML_PCT="n/a"
if [ "$QML_STATUS" -ne 0 ]; then
    fail=1
fi

# --------------------------------------------------------------- report -------
echo ""
echo "==================================================================="
echo "Rust: ${RUST_PCT}% | C++: ${CPP_PCT}% | merged: ${MERGED_PCT}% | QML behaviors: ${QML_PCT}%"
echo "==================================================================="

exit "$fail"
