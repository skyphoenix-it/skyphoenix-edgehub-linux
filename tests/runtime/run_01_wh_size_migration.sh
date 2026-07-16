#!/usr/bin/env bash
# Scenario 01 — w/h → named-size migration on a real persisted config.
#
# Seeds a config whose ui_state still speaks the OLD `{w,h}` span vocabulary
# (per the migration rules documented in ui/qml/DashboardStore.qml), launches
# the REAL hub, and asserts the doc it persists back:
#   * every tile now carries a LEGAL named `size` — with the exact expected
#     values from the migration table (w/cols → short-axis fraction, h → thirds,
#     unsupported sizes coerced DOWN to the largest declared shape);
#   * the dead vocabulary is gone (no tile `w`/`h`, no page `cols`,
#     no appearance `gridCols`);
#   * no tile is lost and per-widget settings survive;
#   * a SECOND launch over the migrated doc is idempotent (sizes unchanged
#     after another real save round-trip).
#
# The hub only persists when something schedules a save, so each launch seeds
# the Focus widget one step from a natural completion (running with an expired
# timer) — the same proven save trigger as run_focus_goal_bonus.sh.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/rt_common.sh"
rt_require_hub

RT_WORK="$(mktemp -d "${TMPDIR:-/tmp}/xe-rt01.XXXXXX")"
trap 'rm -rf "$RT_WORK"' EXIT
fail=0

TODAY="$(date +%F)"
focus_settings() { # $1=doneToday — running with an expired timer = save trigger
    printf '{"preset":"classic","phase":"work","running":true,"endEpoch":1600000000000,"pausedRemaining":1500,"doneToday":%s,"day":"%s","points":0,"dailyGoal":9,"rewardPoints":false,"celebrate":false,"autoStartBreak":false}' "$1" "$TODAY"
}

rt_mkroot m
# Old-vocabulary doc: a 2-column page. Expected per the DashboardStore rules:
#   clock-1 w:2 h:1 → frac 1,   1 third  → "1x1"
#   cpu-1   w:1 h:1 → frac 0.5, 1 third  → "0.5x1"
#   focus-1 w:2 h:2 → frac 1,   2 thirds → "1x2", unsupported by focus
#                     (declares up to 1x1.5) → coerced DOWN → "1x1.5"
python3 "$HERE/seed_config.py" "$RT_CFG" >/dev/null <<EOF
{"version":1,"appearance":{"mode":"dark","accent":"#58A6FF","gridCols":2},
 "settings":{"focus-1":$(focus_settings 0)},
 "pages":[{"name":"Main","cols":2,"tiles":[
    {"id":"clock-1","type":"clock","w":2,"h":1},
    {"id":"cpu-1","type":"cpu","w":1,"h":1},
    {"id":"focus-1","type":"focus","w":2,"h":2}]}]}
EOF

echo "Launch 1 — migrate the old vocabulary and persist"
rt_run_hub "$RT_ROOT" 8
rt_assert_live "launch1" "$RT_ROOT" || fail=1

check_doc() { # $1=label  → prints tile map, asserts the migrated shape
    local label="$1"
    local doc; doc="$(rt_read_config "$RT_CFG")"
    local got
    got="$(rt_json "$doc" '"; ".join("%s=%s w=%s h=%s" % (t["id"], t.get("size"), t.get("w"), t.get("h")) for p in d["ui_state"]["pages"] for t in p["tiles"])' 2>/dev/null)" || {
        echo "  [$label] FAIL: persisted ui_state unreadable"; fail=1; return 1; }
    local want="clock-1=1x1 w=None h=None; cpu-1=0.5x1 w=None h=None; focus-1=1x1.5 w=None h=None"
    if [ "$got" = "$want" ]; then
        echo "  [$label] PASS: $got"
    else
        echo "  [$label] FAIL: got  '$got'"
        echo "  [$label]       want '$want'"
        fail=1; return 1
    fi
    # Dead vocabulary must be gone from the page and appearance too.
    local dead
    dead="$(rt_json "$doc" 'str([d["ui_state"]["pages"][0].get("cols"), d["ui_state"]["appearance"].get("gridCols")])')"
    if [ "$dead" = "[None, None]" ]; then
        echo "  [$label] PASS: page cols / appearance gridCols dropped"
    else
        echo "  [$label] FAIL: dead keys survived: $dead"; fail=1
    fi
    # Settings survive migration.
    local goal
    goal="$(rt_json "$doc" 'd["ui_state"]["settings"]["focus-1"]["dailyGoal"]')"
    if [ "$goal" = "9" ]; then
        echo "  [$label] PASS: per-widget settings preserved (focus dailyGoal=9)"
    else
        echo "  [$label] FAIL: focus settings lost (dailyGoal=$goal)"; fail=1
    fi
}
if ! grep -aq "Configuration saved" "$RT_ROOT/hub.log"; then
    echo "  [launch1] FAIL: no save happened — migration assertion would be vacuous"
    fail=1
else
    check_doc "launch1"
fi

echo "Launch 2 — idempotence: the migrated doc round-trips unchanged"
# Re-arm ONLY the focus save trigger; the tiles stay exactly as launch 1 left them.
python3 - "$RT_CFG" "$TODAY" <<'EOF'
import json, sys, tomllib
cfg = sys.argv[1] + "/config.toml"
with open(cfg, "rb") as f:
    ui = json.loads(tomllib.load(f)["ui_state"])
ui["settings"]["focus-1"].update({"running": True, "endEpoch": 1600000000000,
                                  "phase": "work", "doneToday": 0, "day": sys.argv[2]})
ser = json.dumps(ui, separators=(",", ":"))
assert "'" not in ser
import re
with open(cfg) as f: text = f.read()
text = re.sub(r"^ui_state = '.*'$", "ui_state = '%s'" % ser, text, count=1, flags=re.M)
with open(cfg, "w") as f: f.write(text)
EOF
tiles_before="$(rt_json "$(rt_read_config "$RT_CFG")" 'str([(t["id"], t["size"]) for p in d["ui_state"]["pages"] for t in p["tiles"]])')"
rt_run_hub "$RT_ROOT" 8
rt_assert_live "launch2" "$RT_ROOT" || fail=1
if ! grep -aq "Configuration saved" "$RT_ROOT/hub.log"; then
    echo "  [launch2] FAIL: no save happened — idempotence assertion would be vacuous"
    fail=1
else
    tiles_after="$(rt_json "$(rt_read_config "$RT_CFG")" 'str([(t["id"], t["size"]) for p in d["ui_state"]["pages"] for t in p["tiles"]])')"
    if [ "$tiles_after" = "$tiles_before" ]; then
        echo "  [launch2] PASS: second round-trip left every tile size unchanged: $tiles_after"
    else
        echo "  [launch2] FAIL: sizes drifted on relaunch: $tiles_before -> $tiles_after"
        fail=1
    fi
    check_doc "launch2"
fi

echo
if [ "$fail" -ne 0 ]; then echo "RESULT: FAILURE"; exit 1; fi
echo "RESULT: SUCCESS — w/h documents migrate to named sizes, losslessly and idempotently"
