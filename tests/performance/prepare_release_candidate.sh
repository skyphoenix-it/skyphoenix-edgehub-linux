#!/usr/bin/env bash
# Build the fixed, non-instrumented Release binary used by performance gates.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PERFORMANCE_BUILD_DIR="$PROJECT_DIR/cmake-build-release-performance"

if [ "${XENEON_RELEASE_GATE:-0}" != "1" ]; then
    echo "FAIL: performance candidate preparation is release-gate-only" >&2
    exit 2
fi
if [ "$PERFORMANCE_BUILD_DIR" = "$PROJECT_DIR" ] || [ "$PERFORMANCE_BUILD_DIR" = "/" ]; then
    echo "FAIL: unsafe performance build path" >&2
    exit 2
fi

cmake_bin="$(command -v cmake 2>/dev/null || true)"
if [ -z "$cmake_bin" ] && [ -x "$HOME/.local/bin/cmake" ]; then
    cmake_bin="$HOME/.local/bin/cmake"
fi
if [ -z "$cmake_bin" ] || [ ! -x "$cmake_bin" ]; then
    echo "FAIL: cmake is required" >&2
    exit 2
fi

# The coverage candidate has deliberately different code generation. Start a
# fresh, pinned tree so neither gcov instrumentation nor developer cache state
# can influence the CPU/RSS verdict.
rm -rf -- "$PERFORMANCE_BUILD_DIR"
"$cmake_bin" -B "$PERFORMANCE_BUILD_DIR" -S "$PROJECT_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DXENEON_BUILD_TESTS=OFF \
    -DXENEON_QA_HOOKS=OFF \
    -DXENEON_COVERAGE=OFF
# The Rust archive is emitted under core/target rather than inside the CMake
# tree.  A brand-new CMake directory can therefore still see an older archive
# as up to date and skip Cargo entirely.  Cleaning this freshly configured
# target removes that declared output before the candidate build, while leaving
# source and all non-candidate build trees untouched.
"$cmake_bin" --build "$PERFORMANCE_BUILD_DIR" --target clean
"$cmake_bin" --build "$PERFORMANCE_BUILD_DIR"

cache="$PERFORMANCE_BUILD_DIR/CMakeCache.txt"
hub="$PERFORMANCE_BUILD_DIR/xeneon-edge-hub"
manager="$PERFORMANCE_BUILD_DIR/xeneon-edge-manager"
grep -Fxq 'CMAKE_BUILD_TYPE:STRING=Release' "$cache"
grep -Fxq 'CMAKE_INSTALL_PREFIX:PATH=/usr' "$cache"
grep -Fxq 'XENEON_BUILD_TESTS:BOOL=OFF' "$cache"
grep -Fxq 'XENEON_COVERAGE:BOOL=OFF' "$cache"
grep -Fxq 'XENEON_QA_HOOKS:BOOL=OFF' "$cache"
test -x "$hub"
test -x "$manager"
"$hub" --version
"$manager" --version
echo "PASS: fresh non-instrumented performance candidate: $PERFORMANCE_BUILD_DIR"
