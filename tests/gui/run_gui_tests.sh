#!/usr/bin/env bash
# Visible GUI test runner for the EdgeHub Hub + Manager.
#
# Runs every tests/gui/tst_gui_*.qml in a REAL, nested KWin compositor (the same
# compositor as the device) via qmltestrunner under QT_QPA_PLATFORM=wayland, at a
# watchable speed (-mousedelay/-keydelay). Each test captures grabImage() PNG
# evidence into gui-evidence/. A per-run video is stitched from the frames.
#
# Usage:
#   tests/gui/run_gui_tests.sh [--fast] [--record] [-jN] [pattern]
#     --fast     : mousedelay 0 (confirmation re-runs); default is visible speed
#     --record   : also ffmpeg-record the nested XWayland display to a video
#                  (implies -j1 — there is one display to capture)
#     -jN        : run N files concurrently, each in its OWN nested KWin
#                  (default 1). The suite is ~1000 test functions and takes
#                  hours sequentially; -j8 brings it under half an hour. Files
#                  are independent processes over independent stores, and each
#                  file's evidence PNGs carry a per-file prefix, so they do not
#                  collide. Use -j1 when you want to watch (or record) a run.
#     pattern    : only run tst_gui_*<pattern>*.qml
set -u
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/../.." || exit 2
ROOT="$PWD"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

# Both shipped binaries pin the Controls style (app/src/main.cpp:271 and
# manager/src/main.cpp:116 call QQuickStyle::setStyle("Fusion")). Without this
# the suite runs under the user's desktop style (Breeze here), so every control
# under test is a DIFFERENT control than ships — different indicator geometry,
# different colours, different implicit sizes. A pixel assertion tuned to Fusion
# then fails for a reason that has nothing to do with the product.
export QT_QUICK_CONTROLS_STYLE=Fusion

# ── __slot mode ───────────────────────────────────────────────────────────────
# One file's WHOLE bounded unit: start the nested compositor AND run the test in
# THIS process tree, then exit. run_one re-invokes the script this way as the
# child of run_bounded, so the compositor is a DESCENDANT of the watched process.
#
# Fixes the accounting hole found 2026-07-19: run_one used to start KWin and then
# call run_bounded, making the compositor a SIBLING of the bounded process. It
# inherited no `ulimit -v` and _rb_tree_rss_mb never counted its RSS — and
# Wayland client buffers live in the compositor, i.e. the leak went to the one
# process nothing was watching. Now everything a runner can push into KWin is
# inside the budget.
if [ "${1:-}" = "__slot" ]; then
  export XDG_RUNTIME_DIR="$SLOT_XDG"
  base=$(basename "$SLOT_F" .qml)
  # slot % J: displays and socket names are REUSED, so N concurrent files never
  # claim more than J displays however many files the suite has. (Previously
  # `slot` was a monotonic counter, so 20 files meant displays :71..:91.)
  sock="wayland-gui$$-$(( SLOT_N % SLOT_J ))"
  xdisp=":$(( 70 + SLOT_N % SLOT_J ))"
  kwin_wayland --virtual --xwayland --xwayland-display "$xdisp" \
    --width 2560 --height 720 --no-lockscreen --no-global-shortcuts \
    --socket "$sock" > "$SLOT_LOGDIR/kwin-$base.log" 2>&1 &
  kpid=$!
  # SIGKILL and INT/TERM, matching this script's stated policy below: a wedged
  # compositor ignores SIGTERM, and these are throwaway sessions.
  trap 'kill -9 "$kpid" 2>/dev/null' EXIT INT TERM
  for i in $(seq 1 60); do
    [ -S "$XDG_RUNTIME_DIR/$sock" ] && break
    kill -0 "$kpid" 2>/dev/null || { echo "!! nested KWin died for $base"; exit 3; }
    sleep 0.5
  done
  [ -S "$XDG_RUNTIME_DIR/$sock" ] || { echo "!! nested KWin never came up for $base"; exit 3; }
  sleep 1
  WAYLAND_DISPLAY="$sock" QT_QPA_PLATFORM=wayland QT_LOGGING_RULES="qt.qpa.*=false" \
    "$SLOT_QT" -input "$SLOT_F" $SLOT_IMPORTS \
    -mousedelay "$SLOT_MD" -keydelay "$SLOT_KD"
  qrc=$?
  kill -9 "$kpid" 2>/dev/null
  exit $qrc
fi

FAST=0; RECORD=0; PAT=""; J=1
for a in "$@"; do
  case "$a" in
    --fast) FAST=1 ;;
    --record) RECORD=1 ;;
    -j*) J="${a#-j}" ;;
    *) PAT="$a" ;;
  esac
done
case "$J" in ''|*[!0-9]*) echo "!! -jN needs a number"; exit 2 ;; esac
[ "$J" -lt 1 ] && J=1
# Recording captures ONE X display, so a parallel run would record only whichever
# file happened to land on it — silently misleading. Force sequential.
if [ "$RECORD" = 1 ] && [ "$J" -gt 1 ]; then
  echo "==> --record implies -j1 (one display to capture); ignoring -j$J"
  J=1
fi

MOUSEDELAY=250; KEYDELAY=120
[ "$FAST" = 1 ] && MOUSEDELAY=0 && KEYDELAY=0

QT=/usr/lib/qt6/bin/qmltestrunner

command -v qmltestrunner >/dev/null 2>&1 && QT=qmltestrunner

EVID="$ROOT/gui-evidence"
LOGDIR="$ROOT/build/gui-logs"
rm -rf "$EVID" "$LOGDIR"; mkdir -p "$EVID" "$LOGDIR"
PIDFILE="$LOGDIR/kwin.pids"; : > "$PIDFILE"

IMPORTS="-import ui/qml -import ui/qml/widgets -import manager/qml -import tests/ui -import tests/gui"
FILES=$(ls tests/gui/tst_gui_*.qml 2>/dev/null | sort)
[ -n "$PAT" ] && FILES=$(echo "$FILES" | grep -- "$PAT")
[ -z "$FILES" ] && { echo "!! no test files matched '${PAT:-*}'"; exit 2; }

# Per-runner resource bounds — shared implementation, see the rationale there.
# shellcheck source=../../scripts/lib/run_bounded.sh
. "$ROOT/scripts/lib/run_bounded.sh"
RUN_TIMEOUT=${RUN_TIMEOUT:-900}
RUN_MEM_MAX_MB=${RUN_MEM_MAX_MB:-2048}
RUN_AS_MAX_MB=${RUN_AS_MAX_MB:-12288}

# Kill every nested KWin we started (never a stray one from another run).
# SIGKILL, not SIGTERM: a wedged compositor or Qt client can ignore a polite
# signal, and these are throwaway nested sessions with no state worth flushing.
# Trap TERM/INT too — an EXIT-only trap does not run when a CI harness or an
# agent times the script out with SIGTERM, which is exactly when it matters.
cleanup() {
  [ -n "${FFPID:-}" ] && kill -9 "$FFPID" 2>/dev/null
  while read -r p; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done < "$PIDFILE" 2>/dev/null
}
trap cleanup EXIT INT TERM

# start_kwin <socket> <xdisplay> <logfile> -> echoes pid, or empty on failure
start_kwin() {
  local sock="$1" xdisp="$2" log="$3" pid i
  kwin_wayland --virtual --xwayland --xwayland-display "$xdisp" \
    --width 2560 --height 720 --no-lockscreen --no-global-shortcuts \
    --socket "$sock" > "$log" 2>&1 &
  pid=$!
  echo "$pid" >> "$PIDFILE"
  # Wait for the Wayland socket to actually appear (robust under parallel load).
  for i in $(seq 1 60); do
    [ -S "$XDG_RUNTIME_DIR/$sock" ] && break
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 0.5
  done
  [ -S "$XDG_RUNTIME_DIR/$sock" ] || return 1
  sleep 1
  echo "$pid"
}

# run_one <file> <slot> — runs one test file, writes $LOGDIR/<base>.log.
# In parallel mode each file gets a private compositor so a crash in one cannot
# take its neighbours' windows down with it.
run_one() {
  local f="$1" slot="$2" base rc
  base=$(basename "$f" .qml)
  # Bound every runner in BOTH time and memory. On 2026-07-19 a runaway scene-graph
  # walk drove one qmltestrunner to 18.8 GB RSS; the kernel OOM killer fired and took
  # the developer's IDE down with it. An unbounded GUI runner is never acceptable —
  # a test that needs more than $RUN_MEM_MAX_MB or $RUN_TIMEOUT is a broken test.
  if [ "$J" -gt 1 ]; then
    # Compositor + runner together inside ONE bounded tree: re-invoke this same
    # script in __slot mode as the bounded child, so KWin is a descendant.
    run_bounded SLOT_F="$f" SLOT_N="$slot" SLOT_J="$J" SLOT_QT="$QT" \
      SLOT_IMPORTS="$IMPORTS" SLOT_MD="$MOUSEDELAY" SLOT_KD="$KEYDELAY" \
      SLOT_LOGDIR="$LOGDIR" SLOT_XDG="$XDG_RUNTIME_DIR" \
      bash "$SELF" __slot > "$LOGDIR/$base.log" 2>&1
    rc=$?
  else
    run_bounded WAYLAND_DISPLAY="$SOCK" QT_QPA_PLATFORM=wayland QT_LOGGING_RULES="qt.qpa.*=false" \
      "$QT" -input "$f" $IMPORTS -mousedelay "$MOUSEDELAY" -keydelay "$KEYDELAY" \
      > "$LOGDIR/$base.log" 2>&1
    rc=$?
  fi
  case "$rc" in
    97) echo "!! $base was MEMKILLed (>${RUN_MEM_MAX_MB} MiB RSS)" >> "$LOGDIR/$base.log" ;;
    98) echo "!! $base was TIMEKILLed (>${RUN_TIMEOUT}s)" >> "$LOGDIR/$base.log" ;;
  esac
  return 0
}

if [ "$J" -gt 1 ]; then
  echo "==> running $(echo "$FILES" | wc -l) files, $J at a time, each in its own nested KWin"
  slot=0
  for f in $FILES; do
    slot=$((slot+1))
    echo "==> [start] $(basename "$f" .qml)"
    run_one "$f" "$slot" &
    while [ "$(jobs -rp | wc -l)" -ge "$J" ]; do sleep 1; done
  done
  wait
else
  SOCK="wayland-gui$$"
  XDISP=":9$(( $$ % 90 ))"
  echo "==> starting nested KWin (socket=$SOCK xwayland=$XDISP) ..."
  start_kwin "$SOCK" "$XDISP" "$LOGDIR/kwin.log" > /dev/null || {
    echo "!! nested KWin failed to start"; tail "$LOGDIR/kwin.log"; exit 3; }

  if [ "$RECORD" = 1 ]; then
    # Best-effort continuous capture of the nested XWayland root.
    DISPLAY="$XDISP" ffmpeg -hide_banner -loglevel error -y -f x11grab \
       -video_size 2560x720 -framerate 8 -i "$XDISP" "$EVID/session.mp4" 2>/dev/null &
    FFPID=$!
  fi

  for f in $FILES; do
    echo "==> $(basename "$f" .qml)"
    run_one "$f" 0
  done
fi

# Aggregate AFTER the run, walking FILES in sorted order, so the summary reads
# the same whether the files ran sequentially or finished out of order.
TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_SKIP=0; FILECOUNT=0; FAILFILES=""
SUMMARY="$LOGDIR/summary.txt"; : > "$SUMMARY"
FAILLOG="$LOGDIR/failures.txt"; : > "$FAILLOG"

for f in $FILES; do
  base=$(basename "$f" .qml)
  FILECOUNT=$((FILECOUNT+1))
  # QtTest "Totals: N passed, M failed, K skipped ..."
  line=$(grep -E "^Totals:" "$LOGDIR/$base.log" 2>/dev/null | tail -1)
  p=$(echo "$line" | sed -nE 's/.*Totals: ([0-9]+) passed.*/\1/p'); p=${p:-0}
  m=$(echo "$line" | sed -nE 's/.* ([0-9]+) failed.*/\1/p'); m=${m:-0}
  k=$(echo "$line" | sed -nE 's/.* ([0-9]+) skipped.*/\1/p'); k=${k:-0}
  TOTAL_PASS=$((TOTAL_PASS+p)); TOTAL_FAIL=$((TOTAL_FAIL+m)); TOTAL_SKIP=$((TOTAL_SKIP+k))
  printf "%-44s pass=%-4s fail=%-4s skip=%-4s\n" "$base" "$p" "$m" "$k" >> "$SUMMARY"
  if [ "${m:-0}" != "0" ] || [ -z "$line" ]; then
    FAILFILES="$FAILFILES $base"
    echo "===== $base =====" >> "$FAILLOG"
    grep -E "^FAIL!" "$LOGDIR/$base.log" 2>/dev/null | grep -viE "Cannot open: qrc:" >> "$FAILLOG"
    # A file that fails to LOAD prints no Totals line and contributes 0/0/0 —
    # indistinguishable from a clean pass in the totals unless it is called out.
    [ -z "$line" ] && echo "  (no Totals line — file crashed/failed to load; see $base.log)" >> "$FAILLOG"
  fi
done

# Stitch evidence PNGs into a contact-sheet video (2 fps, watchable).
if ls "$EVID"/*.png >/dev/null 2>&1; then
  ( cd "$EVID" && ls tst_*.png sample_*.png 2>/dev/null | sort > frames.txt
    ffmpeg -hide_banner -loglevel error -y -r 2 -f concat -safe 0 \
      -i <(awk '{print "file \x27"$0"\x27"}' frames.txt) \
      -vf "scale=1280:-2:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black" \
      -pix_fmt yuv420p evidence.mp4 2>/dev/null ) || true
fi

echo
echo "==================================================================="
echo " GUI SUITE TOTALS: pass=$TOTAL_PASS fail=$TOTAL_FAIL skip=$TOTAL_SKIP  (files=$FILECOUNT)"
echo " evidence: $EVID   logs: $LOGDIR"
[ -n "$FAILFILES" ] && echo " FAILED FILES:$FAILFILES" && echo " see $FAILLOG"
echo "==================================================================="
[ "$TOTAL_FAIL" = 0 ] && [ -z "$FAILFILES" ] && echo "RESULT: SUCCESS" || echo "RESULT: FAILURE"
