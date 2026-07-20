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

# Both shipped binaries pin the Controls style (app/src/main.cpp:271 and
# manager/src/main.cpp:116 call QQuickStyle::setStyle("Fusion")). Without this
# the suite runs under the user's desktop style (Breeze here), so every control
# under test is a DIFFERENT control than ships — different indicator geometry,
# different colours, different implicit sizes. A pixel assertion tuned to Fusion
# then fails for a reason that has nothing to do with the product.
export QT_QUICK_CONTROLS_STYLE=Fusion

# Every runner is bounded in time and memory. A QML test that leaks must fail
# ITSELF, never the machine — on 2026-07-19 an unbounded qmltestrunner reached
# 18.8 GB and the resulting system-wide OOM killed the developer's IDE.
# tst_manager.qml is the heaviest file here (observed peaks of ~6 GB), so the
# ceiling is set above that but far below anything that endangers the host.
# shellcheck source=lib/run_bounded.sh
. "$PROJECT_DIR/scripts/lib/run_bounded.sh"
RUN_TIMEOUT=${RUN_TIMEOUT:-600}
RUN_MEM_MAX_MB=${RUN_MEM_MAX_MB:-8192}

fail=0
filecount=0
# Per-file stdout is kept so check_qml_diagnostics.sh can scan it. QML runtime
# errors surface as QWARN lines on STDOUT (measured — NOT stderr), and until
# this landed nothing anywhere treated them as failures: the inert
# BackgroundPicker threw a TypeError on every click while three suites reported
# 5/5, 16/16 and 16/16.
QLOGDIR="${QLOGDIR:-$(mktemp -d -t xe-uilogs-XXXXXX)}"
mkdir -p "$QLOGDIR"

for t in tests/ui/tst_*.qml; do
    echo "==> $t"
    filecount=$((filecount+1))
    base=$(basename "$t" .qml)
    # `set -e` must not skip the bookkeeping below, so capture rc explicitly.
    rc=0
    # -maxwarnings 0 = unlimited. QtTest caps messages at 2000 and then prints
    # "Maximum amount of warnings exceeded", DROPPING everything after it —
    # including the QWARN lines check_qml_diagnostics.sh counts. A gate blinded
    # by the noise it exists to measure will silently undercount, which is the
    # exact failure family this suite keeps hitting.
    run_bounded "$QMLTESTRUNNER" -input "$t" "${IMPORTS[@]}" -maxwarnings 0 \
        > >(tee "$QLOGDIR/$base.log") 2>&1 || rc=$?
    case "$rc" in
        0)  ;;
        97) echo "!! $t MEMKILLed (>${RUN_MEM_MAX_MB} MiB RSS) — treat as a leak"; fail=1 ;;
        98) echo "!! $t TIMEKILLed (>${RUN_TIMEOUT}s) — treat as a hang"; fail=1 ;;
        *)  fail=1 ;;
    esac
    # A QML runtime diagnostic fails the file even when every assertion passed.
    "$PROJECT_DIR/scripts/check_qml_diagnostics.sh" "$QLOGDIR/$base.log" || fail=1
done

# Anti-vacuity floor: a glob that matched nothing must not report success.
if [ "$filecount" -eq 0 ]; then
    echo "!! no test files matched tests/ui/tst_*.qml — refusing to report success"
    exit 1
fi

echo "  logs: $QLOGDIR  ($filecount files)"
[ "$fail" -eq 0 ] && echo "ALL UI TESTS PASSED" || { echo "SOME UI TESTS FAILED"; exit 1; }
