#!/usr/bin/env bash
# Run the QML widget GUI test suite (qmltestrunner) against the source tree —
# no full C++ build required. Uses the offscreen platform so it runs headless
# in CI, but exercises real layout + real mouse/key input via QtTest.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Locate qmltestrunner (not always on PATH).
QMLTESTRUNNER="${QMLTESTRUNNER:-}"
if [ -z "$QMLTESTRUNNER" ]; then
    for c in qmltestrunner /usr/lib/qt6/bin/qmltestrunner /usr/lib/qt6/qmltestrunner; do
        if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then QMLTESTRUNNER="$c"; break; fi
    done
fi
[ -n "$QMLTESTRUNNER" ] || { echo "ERROR: qmltestrunner not found (install qt6-declarative)"; exit 1; }

IMPORTS=(-import ui/qml -import ui/qml/widgets -import manager/qml -import tests/ui)
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

fail=0
for t in tests/ui/tst_*.qml; do
    echo "==> $t"
    if ! "$QMLTESTRUNNER" -input "$t" "${IMPORTS[@]}"; then
        fail=1
    fi
done

[ "$fail" -eq 0 ] && echo "ALL UI TESTS PASSED" || { echo "SOME UI TESTS FAILED"; exit 1; }
