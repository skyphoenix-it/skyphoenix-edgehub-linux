# Generic Linux Installation Guide

**Work in progress** — This guide will be completed in Phase 5 (Hardening).

## Building from Source

If your distribution is not directly supported with packages, you can build from source.

### Prerequisites

- Rust 1.75+ (stable)
- C++17 compiler (GCC 12+ or Clang 16+)
- CMake 3.22+
- Qt 6.5+ development headers (QtQuick, QtWayland, QtDBus, QtSvg)
- libglib2.0

### Build Steps

```bash
git clone https://github.com/your-org/xeneon-edge-linux-hub.git
cd xeneon-edge-linux-hub
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build
```

### Distribution-Specific Dependencies

**Fedora:**
```bash
sudo dnf install rust cargo cmake gcc-c++ qt6-qtbase-devel \
  qt6-qtdeclarative-devel qt6-qtwayland-devel qt6-qttools-devel
```

**openSUSE:**
```bash
sudo zypper install rust cargo cmake gcc-c++ qt6-base-devel \
  qt6-declarative-devel qt6-wayland-devel qt6-tools-devel
```

**Debian 12:**
```bash
# Qt 6 may need backports on Debian 12
sudo apt install cargo cmake g++ qt6-base-dev qt6-declarative-dev qt6-wayland-dev
```

### Post-Install

The application installs to `/usr/local/bin/xeneon-edge-hub` by default.

To add a desktop entry manually:
```bash
cp assets/xeneon-edge-hub.desktop ~/.local/share/applications/
```

