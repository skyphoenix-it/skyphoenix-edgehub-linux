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
# Usage:  ./packaging/appimage/build-appimage.sh [--print-name]
# Output: xeneon-edge-hub-<version>-x86_64.AppImage in the repo root.
#
# --print-name prints the artifact name that a real run would produce and exits
# without building anything. It is the seam scripts/check_appimage_update_contract.sh
# uses to assert the version contract below without a 20-minute build.
#
# Updates (E10): the .zsync control file is deliberately NOT generated here.
# It must embed the release tag's download URL, which only the release flow
# knows - scripts/release.sh generates it (via zsyncmake) when this AppImage
# is passed as an --extra artifact. Keeping this script zsync-free also keeps
# the CI appimage job's dependencies unchanged.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

# VERSION must be the RELEASE version, not project(... VERSION 0.1.0): that field
# is deliberately frozen across commits (see CMakeLists.txt) and is NOT what a
# release is called. Deriving the filename from it named EVERY release's AppImage
# "xeneon-edge-hub-0.1.0-x86_64.AppImage" - indistinguishable between releases -
# and, because the value was never passed back to cmake, the binary's own
# appVersion() disagreed with the filename on top of that. scripts/release.sh
# already documents this exact trap for cpack and overrides it there; the same
# trap applied here and did not.
#
# Order: explicit XENEON_VERSION (what a release passes) > git describe > the
# frozen project() version as a last resort. The leading "v" is stripped so this
# matches the pkgver style of every other artifact ("1.0.0-alpha.2", not
# "v1.0.0-alpha.2"); scripts/release.sh does the same with ${VERSION#v}.
#
# NOTE for CI: git describe needs TAGS. actions/checkout@v4 defaults to
# fetch-depth 1, which fetches none, and `--always` then silently degrades to a
# bare commit sha - which UpdateChecker.qml cannot order against a release tag,
# so the AppImage would never report an available update. The appimage job in
# .github/workflows/distro.yml pins fetch-depth: 0 for exactly this reason.
VERSION="${XENEON_VERSION:-$(git -C "$REPO" describe --tags --always --dirty 2>/dev/null || true)}"
VERSION="${VERSION#v}"
[ -n "$VERSION" ] || VERSION="$(grep -Po 'project\(.*VERSION \K[0-9.]+' CMakeLists.txt | head -1)"
BUILD="$REPO/build-appimage"
APPDIR="$BUILD/AppDir"
TOOLS="$BUILD/tools"
export ARCH=x86_64

# Name the artifact ourselves; appimagetool would otherwise derive it from the
# desktop file's Name= ("Xeneon_Edge_Linux_Hub-x86_64.AppImage"). Computed here
# rather than just before the linuxdeploy call so --print-name can report the
# exact name a real run produces without needing Qt or a build.
export OUTPUT="xeneon-edge-hub-${VERSION}-${ARCH}.AppImage"

# Self-update discovery. Embedded in the binary as `X-AppImage-UpdateInformation`
# so AppImageUpdate/appimaged can find and delta-patch to the newest release
# WITHOUT the user knowing any URL. `latest` = always the newest GitHub release;
# the wildcard matches the versioned artifact name (the version is part of it, by
# design - see the pkgver trap). This is the DISCOVERY half; the .zsync that this
# points at carries the versioned target URL for the actual byte delta (release.sh
# builds it with zsyncmake -u against the versioned download). Both halves are
# required and are checked together by scripts/check_appimage_update_contract.sh.
# LDAI_* is what linuxdeploy's appimage plugin reads; UPDATE_INFORMATION is the
# older appimagetool name - set both so it works regardless of tool vintage.
export LDAI_UPDATE_INFORMATION="gh-releases-zsync|skyphoenix-it|skyphoenix-edgehub-linux|latest|xeneon-edge-hub-*-${ARCH}.AppImage.zsync"
export UPDATE_INFORMATION="$LDAI_UPDATE_INFORMATION"

if [ "${1:-}" = "--print-name" ]; then
  printf '%s\n' "$OUTPUT"
  exit 0
fi

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

echo "==> Building (Release) into an AppDir ($OUTPUT)"
# -DXENEON_VERSION_OVERRIDE is what makes the binary's ConfigBridge.appVersion()
# agree with the filename above. Without it cmake re-derives its own version from
# git describe, which in a shallow CI checkout is a bare sha that
# UpdateChecker.qml cannot order against a release tag - so the in-app check
# would report "no comparable version" and never surface an update, in the one
# install kind that is actually pointed at the .zsync path.
cmake -B "$BUILD" -S "$REPO" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
  -DXENEON_VERSION_OVERRIDE="$VERSION" -Wno-dev
cmake --build "$BUILD" -j"$(nproc)"
rm -rf "$APPDIR"
DESTDIR="$APPDIR" cmake --install "$BUILD"

# linuxdeploy resolves each ELF's NEEDED entries against the loader search path.
# A Qt that is not in the ldconfig cache (aqtinstall, /opt/Qt/...) is invisible
# without this, and the qt plugin fails with "Could not find dependency:
# libQt6DBus.so.6" - or worse, reports "Found Qt modules:" (empty) and silently
# produces an AppImage with no Qt in it at all.
export LD_LIBRARY_PATH="$QT_LIBS:${LD_LIBRARY_PATH:-}"

# The QML is compiled into the binaries via qrc, so there are no external .qml for
# qmlimportscanner to read - point QML_SOURCES_PATHS at the source tree so the Qt
# plugin still bundles the right QML runtime modules (QtQuick, Controls, Effects,
# Shapes, Dialogs, VirtualKeyboard, …). Without this the lazily-imported modules
# are missing and the app STILL starts cleanly, then fails when a widget loads.
export QML_SOURCES_PATHS="$REPO/ui/qml:$REPO/manager/qml"
export EXTRA_QT_MODULES="waylandcompositor svg virtualkeyboard"
# linuxdeploy-plugin-qt only deploys the xcb platform plugin by default. The hub
# targets Wayland on the device, and CI/headless runs need offscreen.
export EXTRA_PLATFORM_PLUGINS="libqoffscreen.so;libqwayland-generic.so;libqwayland-egl.so"

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
echo "    installed on the host - an AppImage cannot ship a udev rule. See"
echo "    packaging/udev/99-xeneon-edge.rules."
