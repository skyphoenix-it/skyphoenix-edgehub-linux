#!/usr/bin/env bash
# Build a portable AppImage of the Xeneon Edge Linux Hub (bundles Qt).
#
# Requires (downloaded automatically if missing, into build-appimage/tools):
#   - linuxdeploy + linuxdeploy-plugin-qt   (https://github.com/linuxdeploy)
# and on the build host: cmake, a C++ toolchain, Rust (cargo), and a Qt6 >= 6.5
# install with qmake6 on PATH.
#
# Build host choice matters: an AppImage's glibc floor is the build host's. CI
# builds this on Ubuntu 24.04 with upstream Qt 6.7 (aqtinstall) rather than
# 24.04's own Qt 6.4.2, which is too old for QtQuick.Effects. That combination
# gives a modern Qt on an old glibc, which is the whole point of the format.
#
# Verified: built here and smoke-tested in a bare ubuntu:24.04 container with no
# Qt installed. See .github/workflows/distro.yml (appimage / appimage-smoke).
#
# Usage:  ./packaging/appimage/build-appimage.sh
# Output: xeneon-edge-hub-<version>-x86_64.AppImage in the repo root.
#
# Updates (E10): the .zsync control file is deliberately NOT generated here.
# It must embed the release tag's download URL, which only the release flow
# knows — scripts/release.sh generates it (via zsyncmake) when this AppImage
# is passed as an --extra artifact. Keeping this script zsync-free also keeps
# the CI appimage job's dependencies unchanged.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
VERSION="$(grep -Po 'project\(.*VERSION \K[0-9.]+' CMakeLists.txt | head -1)"
BUILD="$REPO/build-appimage"
APPDIR="$BUILD/AppDir"
TOOLS="$BUILD/tools"
export ARCH=x86_64

command -v qmake6 >/dev/null || { echo "ERROR: qmake6 not on PATH (need Qt6 >= 6.5)"; exit 1; }
QT_LIBS="$(qmake6 -query QT_INSTALL_LIBS)"

mkdir -p "$TOOLS"
_get() { # url -> tools/name (chmod +x); progress goes to stderr, path to stdout
  local url="$1" out="$TOOLS/$(basename "$1")"
  [ -x "$out" ] || { echo "==> fetching $(basename "$out")" >&2; curl -fL "$url" -o "$out" >&2; chmod +x "$out"; }
  echo "$out"
}
LD="$(_get https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage)"
_get https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage >/dev/null
export PATH="$TOOLS:$PATH"

# Containers/CI have no FUSE, so the linuxdeploy AppImages cannot mount themselves.
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"

echo "==> Building (Release) into an AppDir"
cmake -B "$BUILD" -S "$REPO" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev
cmake --build "$BUILD" -j"$(nproc)"
rm -rf "$APPDIR"
DESTDIR="$APPDIR" cmake --install "$BUILD"

# linuxdeploy resolves each ELF's NEEDED entries against the loader search path.
# A Qt that is not in the ldconfig cache (aqtinstall, /opt/Qt/...) is invisible
# without this, and the qt plugin fails with "Could not find dependency:
# libQt6DBus.so.6" — or worse, reports "Found Qt modules:" (empty) and silently
# produces an AppImage with no Qt in it at all.
export LD_LIBRARY_PATH="$QT_LIBS:${LD_LIBRARY_PATH:-}"

# The QML is compiled into the binaries via qrc, so there are no external .qml for
# qmlimportscanner to read — point QML_SOURCES_PATHS at the source tree so the Qt
# plugin still bundles the right QML runtime modules (QtQuick, Controls, Effects,
# Shapes, Dialogs, VirtualKeyboard, …). Without this the lazily-imported modules
# are missing and the app STILL starts cleanly, then fails when a widget loads.
export QML_SOURCES_PATHS="$REPO/ui/qml:$REPO/manager/qml"
export EXTRA_QT_MODULES="waylandcompositor svg virtualkeyboard"
# linuxdeploy-plugin-qt only deploys the xcb platform plugin by default. The hub
# targets Wayland on the device, and CI/headless runs need offscreen.
export EXTRA_PLATFORM_PLUGINS="libqoffscreen.so;libqwayland-generic.so;libqwayland-egl.so"

# Name the artifact ourselves; appimagetool would derive it from the desktop file
# Name= ("Xeneon_Edge_Linux_Hub-x86_64.AppImage").
export OUTPUT="xeneon-edge-hub-${VERSION}-${ARCH}.AppImage"

# --executable is required for BOTH binaries. linuxdeploy will not scan
# AppDir/usr/bin on its own here, and if nothing is scanned the qt plugin has no
# Qt libraries to key off, finds no modules, and emits an empty 29MB "AppImage".
"$LD" --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/xeneon-edge-hub" \
  --executable "$APPDIR/usr/bin/xeneon-edge-manager" \
  --desktop-file "$APPDIR/usr/share/applications/xeneon-edge-hub.desktop" \
  --icon-file "$APPDIR/usr/share/icons/hicolor/256x256/apps/xeneon-edge-hub.png" \
  --plugin qt \
  --output appimage

echo "==> Done: $OUTPUT"
echo
echo "    The AppImage bundles Qt but NOT the OpenGL/fontconfig stack: linuxdeploy"
echo "    excludes those on purpose, because a bundled libGL breaks on hosts with a"
echo "    different (e.g. NVIDIA) driver. The host must provide libGL/libGLX/"
echo "    libOpenGL/libEGL/libfontconfig + fonts. Every normal desktop has them; a"
echo "    bare container does not (see the appimage-smoke job)."
echo
echo "    Note: the orientation-sensor udev rule (auto-rotate) still has to be"
echo "    installed on the host — an AppImage cannot ship a udev rule. See"
echo "    packaging/udev/99-xeneon-edge.rules."
