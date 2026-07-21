# rt_common.sh - shared plumbing for the runtime E2E scenarios. Source, don't run.
#
# Conventions (every scenario follows them - see tests/runtime/README.md):
#   * exit 0 pass, 1 fail, 77 skip (no hub binary)
#   * each hub run gets its OWN XDG_CONFIG_HOME and XDG_RUNTIME_DIR (single-
#     instance lock + control socket isolation; QLockFile and the control
#     socket both honour XDG_RUNTIME_DIR)
#   * runs are bounded with `timeout -s KILL` - SIGKILL, not SIGTERM, because
#     the hub's graceful-shutdown handler can hang on sensor/socket teardown.
#     rc 137 therefore means "the hub was ALIVE for the whole window", which
#     doubles as the liveness gate. Scenarios that depend on a run's PERSISTED
#     outcome rely on the debounced store save (~0.5-2 s after the trigger),
#     never on shutdown-time saving - so a hard kill is safe, and no scenario
#     may SIGKILL a hub *before* its expected save has had time to land.
#   * NEVER `pkill -f xeneon-edge-hub` - it matches this script's own command
#     line and any real hub the user has open. `timeout` reaps each run.
#   * run dirs stay SHORT (mktemp under /tmp): the control socket path must fit
#     sockaddr_un (~107 bytes).

RT_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RT_PROJECT_DIR="$(cd "$RT_HERE/../.." && pwd)"

rt_find_hub() {
    if [ -n "${XENEON_HUB:-}" ] && [ -x "${XENEON_HUB}" ]; then echo "$XENEON_HUB"; return; fi
    if [ -x "$RT_PROJECT_DIR/build/xeneon-edge-hub" ]; then echo "$RT_PROJECT_DIR/build/xeneon-edge-hub"; return; fi
    if command -v xeneon-edge-hub >/dev/null 2>&1; then command -v xeneon-edge-hub; return; fi
    echo ""
}

# rt_require_hub - resolve the binary into $HUB or exit 77 (suite-level SKIP).
rt_require_hub() {
    HUB="$(rt_find_hub)"
    if [ -z "$HUB" ]; then
        echo "SKIP: no hub binary found (set XENEON_HUB, build ./build/xeneon-edge-hub, or install it)"
        exit 77
    fi
    echo "Hub: $HUB"
}

# rt_mkroot <name> - create an isolated root: $RT_ROOT with config/ and run/.
# Prints nothing; sets RT_ROOT and RT_CFG (the hub's config dir inside it).
rt_mkroot() {
    RT_ROOT="$RT_WORK/$1"
    RT_CFG="$RT_ROOT/config/xeneon-edge-hub"
    mkdir -p "$RT_CFG" "$RT_ROOT/run"
    chmod 700 "$RT_ROOT/run"
}

# rt_run_hub <root> <seconds> [VAR=VALUE ...] - run the hub headless, bounded.
# Log lands in <root>/hub.log; sets RT_RC (137 = ran the full window).
#
# Extra HUB CLI flags: set the RT_HUB_ARGS array before calling (it is passed
# after --windowed and cleared by nobody - reset it yourself between runs):
#   RT_HUB_ARGS=(--reset-wizard); rt_run_hub "$RT_ROOT" 8; RT_HUB_ARGS=()
rt_run_hub() {
    local root="$1" secs="$2"; shift 2
    # --foreground: timeout signals ONLY the hub, not a whole new process
    # group - without it the group-kill also nukes the invoking subshell and
    # bash prints an alarming (but expected) "Killed" job notice for every run.
    # ulimit -v: an address-space ceiling inherited by the hub and anything it
    # spawns. `timeout` already bounds the clock; this bounds memory. A runaway
    # hub then fails its own allocation and aborts, instead of growing until the
    # kernel fires a SYSTEM-WIDE OOM and picks an unrelated victim (on
    # 2026-07-19 that victim was the developer's IDE). Deliberately NOT a cgroup
    # cap - see scripts/lib/run_bounded.sh for why.
    ( ulimit -v $(( ${RT_HUB_AS_MAX_MB:-8192} * 1024 )) 2>/dev/null
      exec env "$@" \
        XDG_CONFIG_HOME="$root/config" XDG_RUNTIME_DIR="$root/run" \
        QT_QPA_PLATFORM=offscreen \
        timeout --foreground -s KILL "$secs" "$HUB" --windowed \
            ${RT_HUB_ARGS[@]+"${RT_HUB_ARGS[@]}"} ) >"$root/hub.log" 2>&1
    RT_RC=$?
}

# rt_assert_live <name> <root> - the run must have lasted its full window
# (rc 137 = timeout SIGKILLed a live hub) and actually come up (control server
# bound). Guards every scenario against the vacuous green of a hub that died
# on launch: a dead hub also "makes no request" and "changes no config".
rt_assert_live() {
    local name="$1" root="$2"
    if [ "$RT_RC" -ne 137 ]; then
        echo "  [$name] FAIL: hub exited early (rc=$RT_RC, expected to live the whole window) - see $root/hub.log"
        return 1
    fi
    if ! grep -aq "ControlServer listening" "$root/hub.log"; then
        echo "  [$name] FAIL: hub never brought up its control server - see $root/hub.log"
        return 1
    fi
    return 0
}

# rt_start_sink <dir> - start the loopback HTTP sink; sets RT_SINK_PID,
# RT_SINK_PORT, RT_SINK_LOG. Caller must rt_stop_sink (or trap it).
rt_start_sink() {
    local dir="$1"
    RT_SINK_LOG="$dir/sink-requests.log"
    local portfile="$dir/sink-port"
    rm -f "$portfile"
    python3 "$RT_HERE/http_sink.py" "$RT_SINK_LOG" "$portfile" &
    RT_SINK_PID=$!
    local i
    for i in $(seq 1 50); do
        [ -s "$portfile" ] && break
        sleep 0.1
    done
    if [ ! -s "$portfile" ]; then
        echo "FAIL: loopback HTTP sink did not start"
        return 1
    fi
    RT_SINK_PORT="$(cat "$portfile")"
    return 0
}

rt_stop_sink() {
    [ -n "${RT_SINK_PID:-}" ] && kill "$RT_SINK_PID" 2>/dev/null
    wait "$RT_SINK_PID" 2>/dev/null
    RT_SINK_PID=""
}

# rt_sink_count - how many requests the sink has recorded so far.
rt_sink_count() { grep -c . "$RT_SINK_LOG" 2>/dev/null || true; }

# rt_read_config <config_dir> - dump {first_run_complete, ui_state, raw_ui_state}.
rt_read_config() { python3 "$RT_HERE/read_config.py" "$1"; }

# rt_json <json> <python-expr over d> - evaluate a python expression against a
# parsed JSON document (bound as `d`), printing the result.
rt_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print('"$2"')'
}
