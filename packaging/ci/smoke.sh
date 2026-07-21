#!/usr/bin/env bash
# Runtime smoke for an INSTALLED xeneon-edge-hub, run inside a clean distro
# container by .github/workflows/distro.yml.
#
# Why not just `--version`: it returns before the QML engine loads, so it proves
# only that the ELF links against its .so deps. The dependency that actually
# breaks is a QML module - those are dlopen'd plugins, invisible to
# dpkg-shlibdeps/rpm autoreqs - and the failure mode is a package that installs
# perfectly and then dies on launch. So this launches the real dashboard.
set -uo pipefail

export QT_QPA_PLATFORM=offscreen
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

command -v xeneon-edge-hub >/dev/null || { echo "FAIL: xeneon-edge-hub not on PATH"; exit 1; }

echo "--- xeneon-edge-hub --version"
xeneon-edge-hub --version 2>&1 | head -3

LOG="$(mktemp)"
# Reap the hub and the temp log on ANY exit path, including SIGINT/SIGTERM.
# Without this a CI timeout or a Ctrl-C orphans a running GUI hub.
cleanup_smoke() { [ -n "${PID:-}" ] && kill -9 "$PID" 2>/dev/null; rm -f "$LOG"; }
trap cleanup_smoke EXIT INT TERM

echo "--- launching dashboard offscreen (10s)"
# Address-space ceiling: a runaway hub must fail its own allocation rather than
# grow until the kernel fires a system-wide OOM. See scripts/lib/run_bounded.sh.
( ulimit -v $(( ${SMOKE_AS_MAX_MB:-8192} * 1024 )) 2>/dev/null
  exec xeneon-edge-hub ) >"$LOG" 2>&1 &
PID=$!
sleep 10

RC=0
if kill -0 "$PID" 2>/dev/null; then
  echo "RESULT: still running after 10s"
  # SIGTERM first, but never wait on it unboundedly: the hub's graceful-shutdown
  # handler is documented to hang on sensor/socket teardown (tests/runtime/
  # rt_common.sh). Escalate to SIGKILL rather than blocking forever in `wait`.
  kill -TERM "$PID" 2>/dev/null
  for _ in $(seq 1 20); do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
  kill -9 "$PID" 2>/dev/null
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
  echo "FAIL: QML module/plugin resolution error above - the package is missing a dependency"
  RC=1
fi

# ── Phase 2: every imported QML module is actually installed ────────────────
# Launching only proves the STARTUP path resolves. main.qml imports just
# QtQuick/Controls/Layouts/Window/VirtualKeyboard; QtQuick.Effects, QtQuick.Shapes
# (backgrounds) and QtQuick.Dialogs (manager) are reached through lazily-loaded
# widgets, so deleting them still yields a clean 10s launch - verified. Those are
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
  # ANTI-VACUITY: an empty MODULES makes the loop below iterate zero times, so
  # RC stays 0 and this prints SMOKE PASS having verified NOTHING. This app
  # cannot import zero Qt modules - an empty list means the grep or SRC_ROOT
  # broke, not that the package is clean. That distinction matters: this check is
  # the only reason we know the Ubuntu .deb needs its nine qml6-module-* Depends
  # (dpkg-shlibdeps cannot see dlopened QML plugins), and a launch alone proves
  # nothing because widgets load lazily.
  MODULE_COUNT=$(printf '%s\n' $MODULES | grep -c . || true)
  if [ "${MODULE_COUNT:-0}" -eq 0 ]; then
    echo "FAIL: derived ZERO QML modules from $SRC_ROOT - the scan is broken."
    echo "      (this app imports many; an empty list is never a clean result)"
    RC=1
  fi
  for m in $MODULES; do
    p="$QML_DIR/$(echo "$m" | tr '.' '/')"
    if [ -f "$p/qmldir" ]; then
      echo "  present: $m"
    else
      echo "  MISSING: $m  (expected $p/qmldir)"
      RC=1
    fi
  done
  [ "$RC" -eq 0 ] && echo "--- verified ${MODULE_COUNT} imported QML module(s) are installed"
  [ "$RC" -ne 0 ] && echo "FAIL: an imported QML module is not installed by the package's dependencies"
else
  echo "--- skipping module check (sources not present; set SRC_ROOT to enable)"
fi

[ "$RC" -eq 0 ] && echo "SMOKE PASS" || echo "SMOKE FAIL"
exit "$RC"
