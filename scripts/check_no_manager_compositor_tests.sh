#!/usr/bin/env bash
# check_no_manager_compositor_tests.sh - the Manager is NEVER tested inside a
# nested KDE Wayland compositor. This gate makes that permanent.
#
# WHY THIS EXISTS
#
# tests/gui/ ran the Manager inside a nested `kwin_wayland`, with the backend
# stubbed out (ManagerHarness: screensJson()="[]", metricsJson()="{}"). Two
# things were wrong with that, and the second one is why the rule is absolute:
#
#   1. It tested a Manager that was not connected to a hub, reading data that
#      did not exist, on a display that was not the Edge. Whatever it proved,
#      it was not that the shipped Manager works.
#
#   2. The measurements it did make were false. Qt's `TestCase.grabImage(item)`
#      grabs the WINDOW and crops at (0,0) to the item's SIZE - it never maps
#      the item's POSITION. The Look tab's preview sits at x=264, so every
#      "did the preview repaint?" assertion was sampling the Manager's nav
#      sidebar, which never changes. Measured 2026-07-20: naive grab distance
#      0, position-aware distance 404.75. Twenty tests reported a product bug
#      that did not exist, and an unknown number of "passing" assertions were
#      passing on furniture.
#
# A compositor layer that adds no fidelity and silently corrupts pixel
# assertions is worse than no layer: it spends review trust without earning it.
#
# THE REPLACEMENT is tests/hardware/manager_*.py - the REAL installed Manager,
# talking to a REAL hub over the control socket, on the REAL Edge. If Manager
# coverage is wanted, it goes there. See tests/hardware/README.md.
#
# This gate is narrow on purpose: it only forbids Manager tests under the
# nested compositor. It says nothing about tests/ui (offscreen component tests
# of Manager QML are fine - they make no pixel/compositor claims).
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

rc=0

# 1. No Manager test files under the compositor suite.
offenders=$(ls tests/gui/tst_gui_mgr_*.qml 2>/dev/null || true)
if [ -n "$offenders" ]; then
    echo "!! FAIL: Manager tests found under the nested compositor suite:"
    echo "$offenders" | sed 's/^/     /'
    echo "   The Manager is tested against a REAL hub in tests/hardware/, never"
    echo "   inside kwin_wayland. See the header of this script."
    rc=1
fi

# 2. No Manager harness that would let one be written.
if [ -e tests/gui/ManagerHarness.qml ]; then
    echo "!! FAIL: tests/gui/ManagerHarness.qml exists."
    echo "   It hosts the Manager with a stubbed backend inside a nested"
    echo "   compositor. That is the thing this gate forbids."
    rc=1
fi

# 3. No compositor test may instantiate the Manager window directly, which is
#    how a Manager test would come back without the word "mgr" in its name.
sneaky=$(grep -ln "Manager\.qml" tests/gui/*.qml 2>/dev/null || true)
if [ -n "$sneaky" ]; then
    echo "!! FAIL: a tests/gui file loads manager/qml/Manager.qml:"
    echo "$sneaky" | sed 's/^/     /'
    rc=1
fi

# ANTI-VACUITY: this gate must always have a subject directory to check. If
# tests/gui vanishes or is renamed, a silent pass here would look identical to
# compliance - which is precisely the failure mode this repo keeps hitting.
if [ ! -d tests/gui ]; then
    echo "!! FAIL: tests/gui/ does not exist - this gate had nothing to check."
    echo "   Refusing to report success for a directory that is not there."
    exit 1
fi
gui_files=$(ls tests/gui/tst_gui_*.qml 2>/dev/null | wc -l)
if [ "$gui_files" -eq 0 ]; then
    echo "!! FAIL: tests/gui/ contains no tst_gui_*.qml at all - nothing checked."
    exit 1
fi

[ "$rc" -eq 0 ] && echo "OK: no Manager tests under the nested compositor ($gui_files gui files scanned)"
exit $rc
