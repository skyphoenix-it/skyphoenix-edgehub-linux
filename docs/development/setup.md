# Development Guide

**Current Phase: Phase 1 - Application Shell**
Last updated: 2026-07-11

---

## Prerequisites

### Rust
Install Rust via rustup:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# Then restart shell or: source ~/.cargo/env (bash) / source ~/.cargo/env.fish (fish)
```

Verify:
```bash
rustc --version  # 1.75+
cargo --version
```

### C++ Compiler & CMake

**CachyOS / Arch Linux:**
```bash
sudo pacman -S cmake gcc
```

**Ubuntu 24.04 LTS:**
```bash
sudo apt install cmake g++
```

### Qt 6

**CachyOS / Arch Linux:**
```bash
sudo pacman -S qt6-base qt6-declarative qt6-wayland qt6-tools
```

**Ubuntu 24.04 LTS:**
```bash
sudo apt install qt6-base-dev qt6-declarative-dev qt6-wayland-dev qt6-tools-dev
```

---

## Quick Build (Automated)

Use the build script which checks prerequisites and handles Rust + CMake:

```bash
./scripts/build.sh debug     # Debug build
./scripts/build.sh release   # Optimized build
```

## Manual Build

### Step 1: Build Rust Core Library

```bash
cd core
cargo build          # Debug
cargo build --release  # Release
```

The output is `core/target/{debug,release}/libxeneon_core.a` - a static library with 30 exported FFI symbols.

### Step 2: Build C++/QML Application

```bash
cd ..
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j$(nproc)
```

### Step 3: Run

```bash
./build/xeneon-edge-hub
```

---

## Testing

### Rust (Self-contained - no system deps beyond Rust)
```bash
cd core
cargo test           # 15 tests, ~0.1s
cargo clippy -- -D warnings
cargo fmt -- --check
```

### Full application (requires Qt6 display)
```bash
./build/xeneon-edge-hub --safe-mode   # Skip widgets
./build/xeneon-edge-hub --reset       # Reset config
./build/xeneon-edge-hub --reset-wizard  # Re-run first-run wizard
```

---

## Debugging

```bash
# Rust logging control
RUST_LOG=xeneon_core=debug ./build/xeneon-edge-hub
RUST_LOG=trace ./build/xeneon-edge-hub

# Backtrace on panic
RUST_BACKTRACE=1 ./build/xeneon-edge-hub

# QML debugging
QT_QPA_EGLFS_DEBUG=1 ./build/xeneon-edge-hub

# Wayland debugging
WAYLAND_DEBUG=1 ./build/xeneon-edge-hub
```

---

## Project Structure

```
skyphoenix-edgehub-linux/
├── core/                   # Rust core library (xeneon-core)
│   ├── Cargo.toml
│   ├── xeneon_core.h       # C FFI header
│   └── src/
│       ├── lib.rs          # Module declarations
│       ├── config.rs       # Configuration (TOML, XDG, serialization)
│       ├── display.rs      # EDID parsing, display identity
│       ├── ffi.rs          # C-compatible FFI (30 exported functions)
│       ├── logging.rs      # Structured logging (tracing)
│       └── metrics.rs      # System metrics (/proc, /sys, hwmon)
├── app/
│   └── src/
│       └── main.cpp        # C++ Qt entry point
├── ui/
│   ├── qml.qrc             # Qt resource file
│   └── qml/
│       ├── main.qml        # Application window
│       ├── FirstRunWizard.qml  # 4-step onboarding wizard
│       └── Dashboard.qml   # Clock, CPU, RAM, focus timer widgets
├── assets/
│   └── xeneon-edge-hub.desktop
├── scripts/
│   └── build.sh            # Automated build with dependency checks
├── docs/                   # Full documentation tree
├── .github/workflows/
│   └── ci.yml              # CI pipeline
├── CMakeLists.txt          # Root build file
└── README.md
```

## Conventional Commits

```
feat: add display enumeration support
fix: correct EDID hash calculation for DisplayPort
docs: update installation guide for Ubuntu 24.04
test: add widget lifecycle integration tests
refactor: extract sensor polling to async module
chore: update Qt dependency to 6.7
perf: reduce memory allocations in config parser
```

## Current Blockers

- **cmake not installed** on this development machine. Install with:
  ```bash
  sudo pacman -S cmake   # Arch/CachyOS
  ```
  Without cmake, the full C++/QML build cannot be verified locally, but the CI pipeline handles it.
