#!/usr/bin/env bash
# Scenario 08 - duplicate page names are reconciled on a REAL load→save trip.
#
# The "two Page 5 tabs" bug: renamePage/addPage reject NEW collisions, but a
# config that ALREADY carried two identical page names was never reconciled on
# load, and the user got two indistinguishable tabs. _normaliseDoc in
# DashboardStore.qml now de-duplicates on load (keep the first occurrence,
# disambiguate later ones with " 2", " 3", …).
#
# tests/ui/tst_store_dedup.qml proves that function against a store in isolation.
# What it cannot prove - and what the user actually experiences - is the whole
# round trip through the real binary: that a duplicate-carrying config.toml on
# disk is loaded, reconciled, and SAVED BACK reconciled, so the fix sticks
# instead of re-deriving on every launch. Nothing covered that.
#
# One seed, two launches:
#   1. Three pages all named "Page 5" (+ a Focus tile one step from a natural
#      completion - the battery's proven save trigger, so the hub re-serializes
#      the doc). Asserts: the PERSISTED names are unique and deterministic, the
#      first keeps its name, every tile is still on its own page (dedup renames,
#      it never merges or drops), and the save was real (log + the focus tick).
#   2. Relaunch over the now-deduped file: the names round-trip UNCHANGED - the
#      reconciliation is idempotent and does not creep ("Page 5 2 2" on every
#      boot is exactly the kind of bug a load-time rewrite invites).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/rt_common.sh"
rt_require_hub

RT_WORK="$(mktemp -d "${TMPDIR:-/tmp}/xe-rt08.XXXXXX")"
trap 'rm -rf "$RT_WORK"' EXIT
fail=0

TODAY="$(date +%F)"
rt_mkroot dedup
# doneToday 3 with dailyGoal 9 → the completion tick makes it 4 (no goal bonus in
# play; scenario run_focus_goal_bonus.sh owns that behavior).
python3 "$HERE/seed_config.py" "$RT_CFG" >/dev/null <<EOF
{"version":1,"appearance":{"mode":"dark","accent":"#58A6FF"},
 "settings":{"focus-1":{"preset":"classic","phase":"work","running":true,"endEpoch":1600000000000,"pausedRemaining":1500,"doneToday":3,"day":"$TODAY","points":0,"dailyGoal":9,"rewardPoints":false,"celebrate":false,"autoStartBreak":false}},
 "pages":[{"name":"Page 5","tiles":[{"id":"focus-1","type":"focus","size":"1x1.5"}]},
          {"name":"Page 5","tiles":[{"id":"clock-b","type":"clock","size":"1x1"}]},
          {"name":"Page 5","tiles":[{"id":"cpu-c","type":"cpu","size":"1x1"}]}]}
EOF

names_of() { rt_json "$(rt_read_config "$1")" '[p["name"] for p in d["ui_state"]["pages"]]'; }
tiles_of() { rt_json "$(rt_read_config "$1")" '[[t["id"] for t in p["tiles"]] for p in d["ui_state"]["pages"]]'; }

# ── 1. Load a duplicate-carrying config; the SAVED doc must be reconciled ───
echo "Run 1 - three pages named 'Page 5': the persisted names must be unique"
rt_run_hub "$RT_ROOT" 8
rt_assert_live "dedup" "$RT_ROOT" || fail=1

# The save must be real: without it every assertion below would just be reading
# the seed back (the file the scenario itself wrote) and could never fail.
if grep -aq "Configuration saved" "$RT_ROOT/hub.log"; then
    echo "  [save] PASS: the hub re-serialized the doc (Configuration saved)"
else
    echo "  [save] FAIL: no save - the assertions below would read back the seed, not the hub's output"
    fail=1
fi
if [ "$(rt_json "$(rt_read_config "$RT_CFG")" 'd["ui_state"]["settings"]["focus-1"]["doneToday"]')" = "4" ]; then
    echo "  [save] PASS: focus 3 -> 4 - the save carries the hub's own state, not the seed"
else
    echo "  [save] FAIL: the focus trigger did not fire; this doc is not hub-authored"
    fail=1
fi

if [ "$(names_of "$RT_CFG")" = "['Page 5', 'Page 5 2', 'Page 5 3']" ]; then
    echo "  [dedup] PASS: persisted names are unique and deterministic (first keeps its name)"
else
    echo "  [dedup] FAIL: expected ['Page 5', 'Page 5 2', 'Page 5 3'], got $(names_of "$RT_CFG")"
    fail=1
fi
# Dedup RENAMES; it must never merge pages or drop a tile.
if [ "$(tiles_of "$RT_CFG")" = "[['focus-1'], ['clock-b'], ['cpu-c']]" ]; then
    echo "  [tiles] PASS: all three pages kept their own tile - dedup renamed, it did not merge"
else
    echo "  [tiles] FAIL: tiles moved/merged/dropped: $(tiles_of "$RT_CFG")"
    fail=1
fi

# ── 2. Idempotence: the deduped names must not creep on the next boot ───────
#
# Run 2 must RE-SAVE, or this proves nothing: the focus trigger is spent (run 1
# completed it), so a plain relaunch would persist nothing and the "unchanged"
# comparison would just be re-reading run 1's file - green even against a dedup
# that renames on every boot. (Proven: with a creeping-dedup sabotage this
# assertion still passed until the trigger was re-armed.) So re-arm the SAME
# proven trigger - touching only focus-1's settings, never a page name - and let
# run 2 write the doc back out under its own steam.
echo "Re-arming the focus save trigger for run 2 (settings only; names untouched)"
python3 - "$RT_CFG" "$TODAY" <<'EOF'
import json, re, sys, tomllib
cfg, today = sys.argv[1] + "/config.toml", sys.argv[2]
with open(cfg, "rb") as f:
    ui = json.loads(tomllib.load(f)["ui_state"])
# phase MUST go back to "work": run 1's completion left the timer on a BREAK, and
# FocusWidget only counts a completion toward doneToday when phase === "work"
# (ui/qml/widgets/FocusWidget.qml). Re-arming without this looks armed and never
# fires - which is how the [resave] guard below caught it.
ui["settings"]["focus-1"].update({"phase": "work", "running": True,
                                  "endEpoch": 1600000000000,
                                  "doneToday": 3, "day": today})
ser = json.dumps(ui, separators=(",", ":"))
assert "'" not in ser          # single-quoted TOML literal: no escaping possible
with open(cfg) as f:
    text = f.read()
with open(cfg, "w") as f:
    f.write(re.sub(r"^ui_state = '.*'$", "ui_state = '%s'" % ser, text, count=1, flags=re.M))
print("  re-armed focus-1 (running, expired endEpoch, doneToday=3)")
EOF
echo "Run 2 - relaunch over the deduped file: names must round-trip unchanged"
before="$(names_of "$RT_CFG")"
rt_run_hub "$RT_ROOT" 8
rt_assert_live "idempotent" "$RT_ROOT" || fail=1
# The re-armed trigger must have fired, or the comparison below is vacuous.
if [ "$(rt_json "$(rt_read_config "$RT_CFG")" 'd["ui_state"]["settings"]["focus-1"]["doneToday"]')" = "4" ]; then
    echo "  [resave] PASS: run 2 re-serialized the doc - the names below are hub-authored"
else
    echo "  [resave] FAIL: run 2 did not save; the idempotence check would re-read run 1's file"
    fail=1
fi
after="$(names_of "$RT_CFG")"
if [ "$after" = "$before" ]; then
    echo "  [idempotent] PASS: names unchanged across a second launch ($after)"
else
    echo "  [idempotent] FAIL: names changed on relaunch: $before -> $after (the rename creeps every boot)"
    fail=1
fi

echo
if [ "$fail" -ne 0 ]; then echo "RESULT: FAILURE"; exit 1; fi
echo "RESULT: SUCCESS - duplicate page names are reconciled on load, persisted reconciled, and stable across boots"
