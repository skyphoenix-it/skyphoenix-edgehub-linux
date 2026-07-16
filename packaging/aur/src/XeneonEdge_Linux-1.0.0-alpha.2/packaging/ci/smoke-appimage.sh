#!/usr/bin/env bash
# Smoke an AppImage in a container that has NO Qt installed, by adapting it to
# the shared packaging/ci/smoke.sh contract (binary on PATH + QML_DIR).
#
# Usage: smoke-appimage.sh <path-to-.AppImage> [src-root]
#
# Why extract instead of just running it: containers have no FUSE, so the
# AppImage cannot mount itself. --appimage-extract is the standard CI workaround
# and, usefully, also exposes usr/qml so smoke.sh can verify the bundled QML
# modules directly instead of only observing a launch.
set -euo pipefail

APPIMAGE="$(readlink -f "${1:?usage: smoke-appimage.sh <path-to-.AppImage> [src-root]}")"
SRC="$(readlink -f "${2:-$(pwd)}")"
WORK="$(mktemp -d)"

cd "$WORK"
cp "$APPIMAGE" ./app.AppImage
chmod +x ./app.AppImage
./app.AppImage --appimage-extract >/dev/null

# smoke.sh looks for `xeneon-edge-hub` on PATH.
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexec %s/squashfs-root/AppRun "$@"\n' "$WORK" > "$WORK/bin/xeneon-edge-hub"
chmod +x "$WORK/bin/xeneon-edge-hub"
export PATH="$WORK/bin:$PATH"

# The bundled QML lives inside the AppImage, and a bare container has no qmake6
# for smoke.sh to ask where Qt's qml dir is.
export QML_DIR="$WORK/squashfs-root/usr/qml"
export SRC_ROOT="$SRC"
export LC_ALL="${LC_ALL:-C.UTF-8}"

echo "=== AppImage: $APPIMAGE"
echo "=== extracted to: $WORK/squashfs-root"
echo "=== bundled Qt libs: $(find "$WORK/squashfs-root" -name 'libQt6*.so*' | wc -l)"
echo "=== system Qt present: $(ls /usr/lib/*/libQt6Core.so* 2>/dev/null | wc -l) (expect 0 — this must be a bare host)"
echo

exec bash "$SRC/packaging/ci/smoke.sh"
