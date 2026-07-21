#!/usr/bin/env bash
# run_bounded - run a child process under a hard wall-clock AND memory ceiling.
#
# WHY THIS EXISTS
# ---------------
# On 2026-07-19 a runaway scene-graph walk in tests/gui/ drove one qmltestrunner
# to 18.8 GB RSS / 78 GB virtual. The kernel fired a SYSTEM-WIDE OOM
# (oom-kill:constraint=CONSTRAINT_NONE ... global_oom) and chose the developer's
# IntelliJ as the victim. No test in this repository may ever be able to do that
# again.
#
# DESIGN CONSTRAINT: never involve the kernel OOM killer.
#   * A cgroup cap (systemd-run -p MemoryMax=) works, but the KERNEL then picks
#     the victim, and the desktop raises a "system is low on memory"
#     notification indistinguishable from a real system-wide OOM. Rejected.
#   * `ulimit -v` caps ADDRESS SPACE. The child's own allocation fails and it
#     aborts itself. The kernel OOM killer is never consulted. This is the hard
#     guarantee, and it cannot be outrun by a fast allocator.
#   * An RSS watchdog on top catches bloat that stays inside the AS limit and
#     reports a clear MEMKILL instead of an opaque allocation abort.
#
# The watchdog sums RSS over the WHOLE PROCESS TREE, so a launcher that forks
# (a runner spawning a compositor, a shell wrapper) cannot hide usage from it.
#
# MEASURED on this repo (tst_gui_mgr_bg_glass_images, real nested KWin):
#   healthy run   VmPeak  2,868 MB   peak RSS    279 MB
#   runaway walk  VmPeak 78,015 MB   peak RSS 18,850 MB
# Defaults sit far above healthy and far below runaway.
#
# USAGE
#   source "$REPO/scripts/lib/run_bounded.sh"
#   run_bounded [VAR=val ...] <command> [args ...]
#   rc=$?     # 97 = MEMKILL, 98 = TIMEKILL, else the child's own status
#
# TUNING (environment)
#   RUN_TIMEOUT      seconds of wall clock            (default 900)
#   RUN_MEM_MAX_MB   tree RSS ceiling, MiB            (default 2048)
#   RUN_AS_MAX_MB    per-process address space, MiB   (default 12288)
#   RUN_POLL         watchdog poll interval, seconds  (default 0.5)

RUN_TIMEOUT=${RUN_TIMEOUT:-900}
RUN_MEM_MAX_MB=${RUN_MEM_MAX_MB:-2048}
RUN_AS_MAX_MB=${RUN_AS_MAX_MB:-12288}
RUN_POLL=${RUN_POLL:-0.5}

# _rb_tree_rss_mb <root-pid> - total RSS (MiB) of the pid and every descendant.
_rb_tree_rss_mb() {
  ps -eo pid=,ppid=,rss= 2>/dev/null | awk -v root="$1" '
    { p[NR]=$1; pp[NR]=$2; r[NR]=$3; n=NR }
    END {
      is[root]=1
      do {
        changed=0
        for (i=1; i<=n; i++)
          if (!is[p[i]] && is[pp[i]]) { is[p[i]]=1; changed=1 }
      } while (changed)
      t=0
      for (i=1; i<=n; i++) if (is[p[i]]) t += r[i]
      printf "%d", t/1024
    }'
}

# _rb_kill_tree <root-pid> - SIGKILL the pid and all descendants, deepest first.
_rb_kill_tree() {
  local root="$1" all
  all=$(ps -eo pid=,ppid= 2>/dev/null | awk -v root="$root" '
    { p[NR]=$1; pp[NR]=$2; n=NR }
    END {
      is[root]=1
      do {
        changed=0
        for (i=1; i<=n; i++)
          if (!is[p[i]] && is[pp[i]]) { is[p[i]]=1; changed=1 }
      } while (changed)
      for (i=1; i<=n; i++) if (is[p[i]]) print p[i]
    }')
  for pid in $all; do [ "$pid" != "$root" ] && kill -9 "$pid" 2>/dev/null; done
  kill -9 "$root" 2>/dev/null
}

run_bounded() {
  # RLIMIT_AS is inherited by every descendant - the hard guarantee.
  ( ulimit -v $((RUN_AS_MAX_MB * 1024)) 2>/dev/null; exec env "$@" ) &
  local pid=$! rss=0 started=$SECONDS

  while kill -0 "$pid" 2>/dev/null; do
    rss=$(_rb_tree_rss_mb "$pid")
    if [ "${rss:-0}" -gt "$RUN_MEM_MAX_MB" ]; then
      _rb_kill_tree "$pid"; wait "$pid" 2>/dev/null
      echo "MEMKILL: process tree exceeded ${RUN_MEM_MAX_MB} MiB RSS (reached ${rss} MiB)" >&2
      return 97
    fi
    # Compare actual elapsed wall-clock time. Counting polling iterations makes
    # a nominal 900-second limit stretch under load because the process scan is
    # additional time on top of each sleep.
    if [ $((SECONDS - started)) -ge "$RUN_TIMEOUT" ]; then
      _rb_kill_tree "$pid"; wait "$pid" 2>/dev/null
      echo "TIMEKILL: process tree exceeded ${RUN_TIMEOUT}s" >&2
      return 98
    fi
    sleep "$RUN_POLL"
  done
  wait "$pid"
}
