#!/usr/bin/env bash
# Build script for Xeneon Edge Linux Hub
# Usage: ./scripts/build.sh [debug|release]

set -euo pipefail

BUILD_TYPE="${1:-debug}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"

case "$BUILD_TYPE" in
    debug)   CMAKE_BUILD_TYPE="Debug" ;;
    release) CMAKE_BUILD_TYPE="Release" ;;
    *) echo "Unknown build type: $BUILD_TYPE"; exit 1 ;;
esac

echo "==> Xeneon Edge Linux Hub Build"
echo "    Build type: ${CMAKE_BUILD_TYPE}"
echo "    Project:    ${PROJECT_DIR}"

# Check prerequisites
echo "==> Checking prerequisites..."

if ! command -v rustc &> /dev/null; then
    echo "ERROR: Rust is not installed."
    echo "  Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    echo "  Then restart your shell or run: source ~/.cargo/env.fish (or .env for bash)"
    exit 1
fi
echo "    Rust: $(rustc --version)"

if ! command -v cmake &> /dev/null; then
    echo "ERROR: CMake is not installed."
    echo "  Arch/CachyOS: sudo pacman -S cmake"
    echo "  Ubuntu/Debian: sudo apt-get install cmake"
    echo "  Fedora: sudo dnf install cmake"
    exit 1
fi
echo "    CMake: $(cmake --version | head -1)"

if ! command -v g++ &> /dev/null; then
    echo "ERROR: C++ compiler (g++) not found."
    echo "  Arch/CachyOS: sudo pacman -S gcc"
    echo "  Ubuntu/Debian: sudo apt-get install g++"
    exit 1
fi
echo "    C++: $(g++ --version | head -1)"

# Check Qt6
if ! pkg-config --exists Qt6Core 2>/dev/null; then
    echo "ERROR: Qt6 development packages not found."
    echo "  Arch/CachyOS: sudo pacman -S qt6-base qt6-declarative"
    echo "  Ubuntu/Debian: sudo apt-get install qt6-base-dev qt6-declarative-dev qt6-wayland-dev"
    echo "  Fedora: sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel"
    exit 1
fi
echo "    Qt6: $(pkg-config --modversion Qt6Core)"

# Step 1: Build Rust core library
echo ""
echo "==> Building Rust core library..."
cd "${PROJECT_DIR}/core"
if [ "$BUILD_TYPE" = "release" ]; then
    cargo build --release
else
    cargo build
fi
echo "    Done."

# Step 2: Configure with CMake
echo ""
echo "==> Configuring CMake..."
cd "${PROJECT_DIR}"
cmake -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
    -DXENEON_QA_HOOKS=ON \
    -G "Unix Makefiles"
# Dev builds enable the QA automation hooks (screenshot capture / auto-open) so
# the test + hardware-E2E suites and marketing-capture flows work. Production
# packaging (packaging/aur/PKGBUILD, CPack) leaves them OFF.

# Step 3: Build
echo ""
echo "==> Building..."
cmake --build "${BUILD_DIR}" -- -j"$(nproc)"

echo ""
echo "==> Build complete!"
echo "    Binary: ${BUILD_DIR}/xeneon-edge-hub"
echo "    Run with: ${BUILD_DIR}/xeneon-edge-hub"
