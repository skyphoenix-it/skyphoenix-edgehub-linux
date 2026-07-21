#!/usr/bin/env bash
# Build (if needed) and run the C++ (QtTest) suite via ctest.
#
# Usage: scripts/run_cpp_tests.sh [build-dir]
# Honors: CMAKE (path to cmake), CTEST (path to ctest), XENEON_COVERAGE=ON,
# XENEON_TEST_BUILD_DIR (default build directory when no argument is supplied).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_BUILD_DIR="$REPO_ROOT/build"
STRICT_BUILD_DIR="$REPO_ROOT/cmake-build-release-tests"
DEFAULT_BUILD_DIR="$DEVELOPER_BUILD_DIR"
case "${XENEON_RELEASE_GATE:-0}" in
    0) ;;
    1) DEFAULT_BUILD_DIR="$STRICT_BUILD_DIR" ;;
    *) echo "ERROR: XENEON_RELEASE_GATE must be 0 or 1" >&2; exit 2 ;;
esac
BUILD_DIR="${1:-${XENEON_TEST_BUILD_DIR:-$DEFAULT_BUILD_DIR}}"
CMAKE="${CMAKE:-cmake}"
CTEST="${CTEST:-ctest}"
command -v "$CMAKE" >/dev/null || CMAKE="$HOME/.local/bin/cmake"
command -v "$CTEST" >/dev/null || CTEST="$HOME/.local/bin/ctest"

COVERAGE_FLAG="-DXENEON_COVERAGE=${XENEON_COVERAGE:-OFF}"

# A strict candidate must never inherit CMake cache entries, binaries, or gcov
# counters from the mutable developer build. Keep the deletion target pinned to
# one repository-owned directory; a caller cannot redirect a release cleanup.
if [ "${XENEON_RELEASE_GATE:-0}" = "1" ]; then
    if [ "$BUILD_DIR" != "$STRICT_BUILD_DIR" ]; then
        echo "ERROR: strict C++ tests must use the dedicated build directory: $STRICT_BUILD_DIR" >&2
        exit 2
    fi
    rm -rf -- "$STRICT_BUILD_DIR"
fi

echo "== Configuring ($BUILD_DIR) with C++ tests =="
# XENEON_QA_HOOKS=ON is REQUIRED for the smoke tests: they drive the real
# binaries via XENEON_GRAB (render one frame → PNG → exit), and that hook is
# compiled out by default (product builds must ignore it). Without this the
# binaries ignore the grab, never exit, and smoke_hub/smoke_manager fail on a
# 30s timeout. The tests QSKIP rather than hang if it is ever off.
"$CMAKE" -B "$BUILD_DIR" -S "$REPO_ROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DXENEON_BUILD_TESTS=ON \
    -DXENEON_QA_HOOKS=ON \
    "$COVERAGE_FLAG"

echo "== Building =="
"$CMAKE" --build "$BUILD_DIR"

# Timestamp the clean counter baseline after compilation and immediately before
# ctest creates the .gcda files consumed by the strict coverage gate.
if [ "${XENEON_RELEASE_GATE:-0}" = "1" ] && [ "${XENEON_COVERAGE:-OFF}" = "ON" ]; then
    find "$BUILD_DIR" -type f -name '*.gcda' -delete
    touch "$BUILD_DIR/.xeneon-release-coverage-reset"
fi

echo "== Running C++ tests (offscreen) =="
# Offscreen keeps the smoke tests (which spin up real Qt windows) headless.
export QT_QPA_PLATFORM=offscreen
"$CTEST" --test-dir "$BUILD_DIR" --output-on-failure
