#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# update-local.sh — build the current checkout and install it, one command.
#
#   ./scripts/update-local.sh              build + sudo pacman -U + restart hub
#   ./scripts/update-local.sh --no-install build only (CI / dry-run)
#   ./scripts/update-local.sh --no-restart install but leave the running hub
#
# The dogfood path for an Arch/CachyOS dev box: pacman stays the owner of the
# installed files (no side-loaded binaries drifting from the package DB), you
# type your password once for `pacman -U`, and the hub restart is a graceful
# SIGTERM — the hub SAVES ITS CONFIG on TERM, and skipping that once cost a
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
    echo "Run as your user, not root — pacman is invoked with sudo only where needed." >&2
    exit 2
fi

echo "==> Building: $(git -C "$REPO" log --oneline -1)"
if ! git -C "$REPO" diff --quiet || ! git -C "$REPO" diff --cached --quiet; then
    echo "    NOTE: working tree is dirty — you are installing uncommitted changes"
    echo "    (the UI version will carry a -dirty suffix so this is visible later)."
fi

cd "$PKGDIR"
makepkg -f

# makepkg -f leaves exactly one package per pkgver; take the newest so a stale
# artifact from an older revision can never be the one we install. (A previous
# release script swept up a stale tarball with a glob — same trap.)
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

if pgrep -x xeneon-edge-hub >/dev/null; then
    echo "==> Restarting the hub (SIGTERM — it saves config on the way out)"
    pkill -TERM -x xeneon-edge-hub
    # Wait for a real exit rather than racing the save: up to 10s.
    for _ in $(seq 1 20); do
        pgrep -x xeneon-edge-hub >/dev/null || break
        sleep 0.5
    done
    if pgrep -x xeneon-edge-hub >/dev/null; then
        echo "    hub did not exit within 10s — NOT killing it harder (that loses"
        echo "    the in-memory config). Investigate, then restart it yourself." >&2
        exit 1
    fi
fi

setsid /usr/bin/xeneon-edge-hub >/dev/null 2>&1 &
sleep 2
if ! pgrep -x xeneon-edge-hub >/dev/null; then
    echo "    hub failed to start — run /usr/bin/xeneon-edge-hub in a terminal to see why." >&2
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

# Restart the Manager too, if it is running. It is a GUI tool, not a persistent
# service, so we only relaunch one when we stopped one — we do NOT pop an
# unwanted window on someone who did not have it open. Unlike the hub it owns no
# config while connected (the hub is the single writer), so a plain SIGTERM is
# safe; we still wait for a clean exit before relaunching so the new process
# never races a dying one for the control socket.
#
# NOTE: match with -f (full command line), NOT -x. Linux truncates a process's
# `comm` to 15 chars, and "xeneon-edge-manager" is 19 → comm is "xeneon-edge-man",
# so `pgrep -x xeneon-edge-manager` never matched and the Manager was silently
# never restarted. (The hub is exactly 15 chars, so -x still works for it.)
if pgrep -f xeneon-edge-manager >/dev/null; then
    echo "==> Restarting the Manager (it was open — bringing it to the new build)"
    pkill -TERM -f xeneon-edge-manager
    for _ in $(seq 1 20); do
        pgrep -f xeneon-edge-manager >/dev/null || break
        sleep 0.5
    done
    if pgrep -f xeneon-edge-manager >/dev/null; then
        echo "    Manager did not exit within 10s; sending SIGKILL (it holds no"
        echo "    unsaved state — the hub owns config while connected)." >&2
        pkill -KILL -f xeneon-edge-manager || true
        sleep 1
    fi
    setsid /usr/bin/xeneon-edge-manager >/dev/null 2>&1 &
    sleep 1
    if pgrep -f xeneon-edge-manager >/dev/null; then
        echo "==> Manager running on the new build"
    else
        echo "    Manager did not come back up — launch xeneon-edge-manager yourself." >&2
    fi
fi
echo "==> Done: $(pacman -Q xeneon-edge-hub) — hub and (if it was open) Manager both on the new build"
