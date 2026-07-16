#!/usr/bin/env bash
# Build (if needed) and run the C++ (QtTest) suite via ctest.
#
# Usage: scripts/run_cpp_tests.sh [build-dir]
# Honors: CMAKE (path to cmake), CTEST (path to ctest), XENEON_COVERAGE=ON.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-$REPO_ROOT/build}"
CMAKE="${CMAKE:-cmake}"
CTEST="${CTEST:-ctest}"
command -v "$CMAKE" >/dev/null || CMAKE="$HOME/.local/bin/cmake"
command -v "$CTEST" >/dev/null || CTEST="$HOME/.local/bin/ctest"

COVERAGE_FLAG="-DXENEON_COVERAGE=${XENEON_COVERAGE:-OFF}"

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

echo "== Running C++ tests (offscreen) =="
# Offscreen keeps the smoke tests (which spin up real Qt windows) headless.
export QT_QPA_PLATFORM=offscreen
"$CTEST" --test-dir "$BUILD_DIR" --output-on-failure
