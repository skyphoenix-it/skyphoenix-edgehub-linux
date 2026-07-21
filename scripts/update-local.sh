#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# update-local.sh - build the current checkout and install it, one command.
#
#   ./scripts/update-local.sh              build + sudo pacman -U + restart hub
#   ./scripts/update-local.sh --no-install build only (CI / dry-run)
#   ./scripts/update-local.sh --no-restart install but leave the running hub
#
# The dogfood path for an Arch/CachyOS dev box: pacman stays the owner of the
# installed files (no side-loaded binaries drifting from the package DB), you
# type your password once for `pacman -U`, and the hub restart is a graceful
# SIGTERM - the hub SAVES ITS CONFIG on TERM, and skipping that once cost a
# whole dashboard layout. Never SIGKILL here.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGDIR="$REPO/packaging/local"
DO_INSTALL=1
DO_RESTART=1
for arg in "$@"; do
    case "$arg" in
        --no-install) DO_INSTALL=0 ;;
        --no-restart) DO_RESTART=0 ;;
        *) echo "unknown flag: $arg (known: --no-install, --no-restart)" >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your user, not root - pacman is invoked with sudo only where needed." >&2
    exit 2
fi

echo "==> Building: $(git -C "$REPO" log --oneline -1)"
if ! git -C "$REPO" diff --quiet || ! git -C "$REPO" diff --cached --quiet; then
    echo "    NOTE: working tree is dirty - you are installing uncommitted changes"
    echo "    (the UI version will carry a -dirty suffix so this is visible later)."
fi

# Pre-flight the sudo credential BEFORE the multi-minute build. Under
# `set -euo pipefail` a password prompt that goes unanswered makes `sudo
# pacman -U` exit non-zero and kills the script instantly - after the package is
# built, before it is installed. That failure mode is near-silent: you are left
# with a fresh .pkg.tar.zst, an untouched system, and no obvious reason why.
# It has now happened for real (r234 built 02:51, last install r229 at 01:57).
if [ "$DO_INSTALL" -eq 1 ] && ! sudo -n true 2>/dev/null; then
    echo "==> pacman needs your password to install. Priming sudo first so the"
    echo "    build is not thrown away by an unanswered prompt at the end."
    if ! sudo -v; then
        echo "!! Could not obtain sudo credentials - aborting BEFORE the build." >&2
        echo "   Run this from an interactive terminal, or pass --no-install." >&2
        exit 2
    fi
fi

cd "$PKGDIR"
makepkg -f

# makepkg -f leaves exactly one package per pkgver; take the newest so a stale
# artifact from an older revision can never be the one we install. (A previous
# release script swept up a stale tarball with a glob - same trap.)
PKG="$(ls -t "$PKGDIR"/xeneon-edge-hub-*.pkg.tar.zst | head -1)"
echo "==> Built: $(basename "$PKG")"

if [ "$DO_INSTALL" -eq 0 ]; then
    echo "==> --no-install: stopping here."
    exit 0
fi

sudo pacman -U "$PKG"

if [ "$DO_RESTART" -eq 0 ]; then
    echo "==> --no-restart: installed; the running hub still has the old code."
    exit 0
fi

# Reopen the Manager BEFORE the hub restart - the ORDER is the whole point. A
# Wayland compositor opens a new window on the ACTIVE output. If the Manager is
# relaunched AFTER the hub takes the Edge fullscreen, the Edge is the active output
# and the Manager opens ON the Edge (wrong: it configures the Edge, it must live on
# your main screen). Relaunching it now - while THIS terminal, on your main
# display, is still the active window - lands it on the main screen. It connects to
# the still-running old hub, and its 2s reconnect timer re-attaches to the new hub
# after the restart below. We only reopen one if one was already open (never pop an
# unwanted window). The Manager also picks a non-Edge screen itself as a fallback.
MGR_WAS_OPEN=0
if pgrep -f xeneon-edge-manager >/dev/null; then
    MGR_WAS_OPEN=1
    echo "==> Closing the open Manager (it will reopen on your main screen, before the hub takes the Edge)"
    pkill -TERM -f xeneon-edge-manager
    for _ in $(seq 1 20); do pgrep -f xeneon-edge-manager >/dev/null || break; sleep 0.5; done
    if pgrep -f xeneon-edge-manager >/dev/null; then
        pkill -KILL -f xeneon-edge-manager || true
        sleep 1
    fi
fi
if [ "$MGR_WAS_OPEN" -eq 1 ]; then
    echo "==> Reopening the Manager on the active (main) screen"
    setsid /usr/bin/xeneon-edge-manager >/dev/null 2>&1 &
    sleep 2   # let it map on the main screen while this terminal is still active
fi

if pgrep -x xeneon-edge-hub >/dev/null; then
    echo "==> Restarting the hub (SIGTERM - it saves config on the way out)"
    pkill -TERM -x xeneon-edge-hub
    # Wait for a real exit rather than racing the save: up to 10s.
    for _ in $(seq 1 20); do
        pgrep -x xeneon-edge-hub >/dev/null || break
        sleep 0.5
    done
    if pgrep -x xeneon-edge-hub >/dev/null; then
        echo "    hub did not exit within 10s - NOT killing it harder (that loses"
        echo "    the in-memory config). Investigate, then restart it yourself." >&2
        exit 1
    fi
fi

setsid /usr/bin/xeneon-edge-hub >/dev/null 2>&1 &
sleep 2
if ! pgrep -x xeneon-edge-hub >/dev/null; then
    echo "    hub failed to start - run /usr/bin/xeneon-edge-hub in a terminal to see why." >&2
    exit 1
fi

# The socket location depends on the installed version: r130+ binds under
# XDG_RUNTIME_DIR (hardened); older builds used /tmp. Report what we see.
RUNTIME_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/xeneon-edge-hub-ctl"
if [ -S "$RUNTIME_SOCK" ]; then
    echo "==> Hub running; control socket at $RUNTIME_SOCK"
elif [ -S /tmp/xeneon-edge-hub-ctl ]; then
    echo "==> Hub running; control socket at /tmp/xeneon-edge-hub-ctl (pre-r130 build)"
else
    echo "==> Hub running; no control socket yet (Manager may not connect)" >&2
fi

# The Manager was already reopened ABOVE, before the hub restart, so it lands on
# the main screen rather than on the freshly-fullscreened Edge. It reconnects to
# this new hub on its own (2s reconnect timer). Just report the outcome.
# (`pgrep -f`, not `-x`: Linux truncates `comm` to 15 chars, and
# "xeneon-edge-manager" is 19, so `-x` never matches it.)
if [ "$MGR_WAS_OPEN" -eq 1 ]; then
    if pgrep -f xeneon-edge-manager >/dev/null; then
        echo "==> Manager reopened on the main screen (reconnecting to the new hub)"
    else
        echo "    Manager did not come back up - launch xeneon-edge-manager yourself." >&2
    fi
fi
# Anti-vacuity: assert the DB actually moved to what we just built. Without
# this the script's final line reports whatever is installed, which reads as
# success even when the install never happened.
BUILT_VER="$(basename "$PKG" | sed -E 's/^xeneon-edge-hub-(.*)-x86_64\.pkg\.tar\.zst$/\1/')"
INSTALLED_VER="$(pacman -Q xeneon-edge-hub 2>/dev/null | awk '{print $2}')"
if [ "$BUILT_VER" != "$INSTALLED_VER" ]; then
    echo "!! INSTALL DID NOT LAND." >&2
    echo "   built:     $BUILT_VER" >&2
    echo "   installed: ${INSTALLED_VER:-<not installed>}" >&2
    echo "   The package was produced but pacman is still on the old version." >&2
    exit 1
fi
echo "==> Done: $(pacman -Q xeneon-edge-hub) - hub and (if it was open) Manager both on the new build"
