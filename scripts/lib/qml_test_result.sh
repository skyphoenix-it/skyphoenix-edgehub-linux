#!/usr/bin/env bash
# Shared anti-vacuity check for one qmltestrunner log.

# xeneon_qml_require_live_totals <log> [label]
# Accept exactly a live, all-green QtTest aggregate: at least one passing check,
# no failures, skips, or blacklisted tests.  qmltestrunner can be replaced by an
# executable that exits zero and prints nothing, so process status alone is not
# evidence that a QML test ran.
xeneon_qml_require_live_totals() {
    local log="${1:?qml log is required}" label="${2:-$1}"
    local line passed failed skipped blacklisted

    line="$(grep -E '^Totals:' "$log" 2>/dev/null | tail -1 || true)"
    if [ -z "$line" ]; then
        echo "!! $label produced no QtTest Totals line; no test execution was proven" >&2
        return 1
    fi

    passed="$(printf '%s\n' "$line" | sed -nE 's/.*Totals: ([0-9]+) passed.*/\1/p')"
    failed="$(printf '%s\n' "$line" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')"
    skipped="$(printf '%s\n' "$line" | sed -nE 's/.* ([0-9]+) skipped.*/\1/p')"
    blacklisted="$(printf '%s\n' "$line" | sed -nE 's/.* ([0-9]+) blacklisted.*/\1/p')"
    passed="${passed:-0}"
    failed="${failed:-0}"
    skipped="${skipped:-0}"
    blacklisted="${blacklisted:-0}"

    if [ "$passed" -lt 1 ] || [ "$failed" -ne 0 ] || \
       [ "$skipped" -ne 0 ] || [ "$blacklisted" -ne 0 ]; then
        echo "!! $label is not a complete live pass: $line" >&2
        return 1
    fi
    return 0
}
