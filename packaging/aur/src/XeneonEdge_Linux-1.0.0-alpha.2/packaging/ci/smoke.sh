#!/usr/bin/env bash
# Runtime smoke for an INSTALLED xeneon-edge-hub, run inside a clean distro
# container by .github/workflows/distro.yml.
#
# Why not just `--version`: it returns before the QML engine loads, so it proves
# only that the ELF links against its .so deps. The dependency that actually
# breaks is a QML module — those are dlopen'd plugins, invisible to
# dpkg-shlibdeps/rpm autoreqs — and the failure mode is a package that installs
# perfectly and then dies on launch. So this launches the real dashboard.
set -uo pipefail

export QT_QPA_PLATFORM=offscreen
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

command -v xeneon-edge-hub >/dev/null || { echo "FAIL: xeneon-edge-hub not on PATH"; exit 1; }

echo "--- xeneon-edge-hub --version"
xeneon-edge-hub --version 2>&1 | head -3

LOG="$(mktemp)"
echo "--- launching dashboard offscreen (10s)"
xeneon-edge-hub >"$LOG" 2>&1 &
PID=$!
sleep 10

RC=0
if kill -0 "$PID" 2>/dev/null; then
  echo "RESULT: still running after 10s"
  kill -TERM "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
else
  wait "$PID" 2>/dev/null
  echo "RESULT: exited early with rc=$?"
  RC=1
fi

echo "--- hub output:"
cat "$LOG"

# Scoped to QML/plugin resolution. Do NOT broaden to a bare "No such file or
# directory": the hidraw orientation-sensor warning is expected in a container
# (no device, no udev rule) and would false-positive.
if grep -qiE 'is not installed|plugin .* not found|cannot load library|QQmlApplicationEngine failed|Failed to load QML' "$LOG"; then
  echo "FAIL: QML module/plugin resolution error above — the package is missing a dependency"
  RC=1
fi

# ── Phase 2: every imported QML module is actually installed ────────────────
# Launching only proves the STARTUP path resolves. main.qml imports just
# QtQuick/Controls/Layouts/Window/VirtualKeyboard; QtQuick.Effects, QtQuick.Shapes
# (backgrounds) and QtQuick.Dialogs (manager) are reached through lazily-loaded
# widgets, so deleting them still yields a clean 10s launch — verified. Those are
# exactly the modules distros split into separate packages, so check them
# directly. The list is derived from the sources, not hand-maintained, so a new
# import cannot silently escape the packaging.
SRC_ROOT="${SRC_ROOT:-$(pwd)}"
if [ -d "$SRC_ROOT/ui/qml" ]; then
  # QML_DIR may be preset by the caller. The AppImage job does that: its modules
  # live inside the extracted AppDir (usr/qml), not in a system Qt prefix, and a
  # bare container has no qmake6 to ask.
  QML_DIR="${QML_DIR:-}"
  if [ -z "$QML_DIR" ] && command -v qmake6 >/dev/null 2>&1; then
    QML_DIR="$(qmake6 -query QT_INSTALL_QML 2>/dev/null)"
  fi
  if [ -z "$QML_DIR" ] || [ ! -d "$QML_DIR" ]; then
    for c in /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib/*/qt6/qml; do
      [ -d "$c" ] && { QML_DIR="$c"; break; }
    done
  fi
  echo "--- QML import root: ${QML_DIR:-<not found>}"

  # QtTest is a test-only import and is intentionally not a runtime dependency.
  MODULES=$(grep -rhoE '^[[:space:]]*import Qt[A-Za-z0-9.]+' \
              "$SRC_ROOT/ui/qml" "$SRC_ROOT/manager" 2>/dev/null \
            | awk '{print $2}' | grep -v '^QtTest$' | sort -u)
  for m in $MODULES; do
    p="$QML_DIR/$(echo "$m" | tr '.' '/')"
    if [ -f "$p/qmldir" ]; then
      echo "  present: $m"
    else
      echo "  MISSING: $m  (expected $p/qmldir)"
      RC=1
    fi
  done
  [ "$RC" -ne 0 ] && echo "FAIL: an imported QML module is not installed by the package's dependencies"
else
  echo "--- skipping module check (sources not present; set SRC_ROOT to enable)"
fi

[ "$RC" -eq 0 ] && echo "SMOKE PASS" || echo "SMOKE FAIL"
exit "$RC"
