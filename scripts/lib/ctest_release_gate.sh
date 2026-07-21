#!/usr/bin/env bash
# ctest adapter used by run_all_tests.sh in strict release mode. ctest normally
# hides stdout for passing QtTest executables, which also hides QSKIP. Verbose
# output plus the shared scanner makes an internal QSKIP release-blocking.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release_gate.sh
. "$SCRIPT_DIR/release_gate.sh"

REAL_CTEST="${XENEON_REAL_CTEST:-ctest}"
case "$(basename "$REAL_CTEST")" in
    ctest) ;;
    *) echo "ERROR: strict CTest adapter requires the real ctest executable" >&2; exit 2 ;;
esac
if ! command -v "$REAL_CTEST" >/dev/null 2>&1; then
    if [ -x "$HOME/.local/bin/ctest" ]; then
        REAL_CTEST="$HOME/.local/bin/ctest"
    else
        echo "ERROR: ctest not found" >&2
        exit 1
    fi
fi

xeneon_run_rejecting_skips "$REAL_CTEST" --verbose "$@"
