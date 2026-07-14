#!/usr/bin/env bash
# run_focus_goal_bonus.sh — end-to-end runtime test for the Focus goal bonus.
#
# Drives the REAL hub binary (not the QML unit harness) through natural session
# completions and asserts the PERSISTED reward in config.toml: the +50 daily-goal
# bonus + "🎯 Goal reached!" celebration must fire exactly ONCE, on the session
# that crosses the goal (done === dailyGoal), never again for sessions past it.
#
# Each scenario seeds an isolated XDG config (a Focus tile one step from the goal,
# running with an expired timer), launches the hub headless for a few seconds so
# its 1 s tick fires advance(true) and the debounced store save writes config.toml,
# then reads the persisted points/count back.
#
# The hub is a long-lived GUI process, so we bound each run with `timeout` (which
# cleanly SIGTERMs it) rather than backgrounding it. Runs fully headless via the
# offscreen QPA platform; each run gets its own XDG_RUNTIME_DIR so the single-
# instance lock and control socket never collide.
#
# Hub binary: $XENEON_HUB, else ./build/xeneon-edge-hub, else the installed
# /usr/bin/xeneon-edge-hub. Exits 0 on pass, 1 on failure, 77 (skip) if no binary.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$HERE/../.." && pwd)"

find_hub() {
    if [ -n "${XENEON_HUB:-}" ] && [ -x "${XENEON_HUB}" ]; then echo "$XENEON_HUB"; return; fi
    if [ -x "$PROJECT_DIR/build/xeneon-edge-hub" ]; then echo "$PROJECT_DIR/build/xeneon-edge-hub"; return; fi
    if command -v xeneon-edge-hub >/dev/null 2>&1; then command -v xeneon-edge-hub; return; fi
    echo ""
}

HUB="$(find_hub)"
if [ -z "$HUB" ]; then
    echo "SKIP: no hub binary found (set XENEON_HUB, build ./build/xeneon-edge-hub, or install it)"
    exit 77
fi
echo "Hub: $HUB"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/xeneon-focus-rt.XXXXXX")"
# `timeout -s KILL` below already reaps each hub run, so no process cleanup is
# needed here — and a `pkill -f xeneon-edge-hub` would be actively dangerous:
# it matches this script's own command line AND any real hub the user has open.
trap 'rm -rf "$WORK"' EXIT

fail=0

# run_scenario <name> <doneToday> <dailyGoal> <expect_points> <expect_done>
run_scenario() {
    local name="$1" done_today="$2" goal="$3" exp_pts="$4" exp_done="$5"
    local root="$WORK/$name"
    local cfg_dir="$root/config/xeneon-edge-hub" run_dir="$root/run"
    mkdir -p "$cfg_dir" "$run_dir"; chmod 700 "$run_dir"

    python3 "$HERE/focus_seed_config.py" "$cfg_dir" "$done_today" "$goal" >/dev/null

    # SIGKILL (not the default SIGTERM): the hub's graceful-shutdown handler can
    # hang on sensor/socket teardown, and we don't need a clean exit — the
    # debounced store save has already written config.toml well before the
    # timeout. 6 s comfortably covers the 1 s tick + ~1.5 s save debounce.
    XDG_CONFIG_HOME="$root/config" XDG_RUNTIME_DIR="$run_dir" \
        QT_QPA_PLATFORM=offscreen timeout -s KILL 9 "$HUB" --windowed >"$root/hub.log" 2>&1
    # timeout → rc 137 (128+SIGKILL) is the expected/normal exit here.

    if grep -q "parse failed" "$root/hub.log"; then
        echo "  [$name] FAIL: hub rejected the seeded config (see $root/hub.log)"
        fail=1; return
    fi

    local got; got="$(python3 "$HERE/focus_read_points.py" "$cfg_dir" 2>/dev/null)"
    local pts done_out
    pts="$(printf '%s' "$got"    | python3 -c 'import json,sys; print(json.load(sys.stdin)["points"])')"
    done_out="$(printf '%s' "$got" | python3 -c 'import json,sys; print(json.load(sys.stdin)["doneToday"])')"

    if [ "$pts" = "$exp_pts" ] && [ "$done_out" = "$exp_done" ]; then
        echo "  [$name] PASS: $got  (expect points=$exp_pts doneToday=$exp_done)"
    else
        echo "  [$name] FAIL: $got  (expect points=$exp_pts doneToday=$exp_done)"
        fail=1
    fi
}

echo "Scenario A — crossing the goal (done 3 -> 4 of 4): one-time +10 +50 bonus"
run_scenario cross 3 4 60 4
echo "Scenario B — past the goal (done 4 -> 5, goal 4): +10 only, no re-fire"
run_scenario past 4 4 10 5

echo
if [ "$fail" -ne 0 ]; then
    echo "RESULT: FAILURE"
    exit 1
fi
echo "RESULT: SUCCESS — Focus goal bonus fires exactly once"
