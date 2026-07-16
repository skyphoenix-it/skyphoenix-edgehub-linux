#!/usr/bin/env bash
# Scenario 02 — org policy enforcement (E9) on the real hub.
#
# Uses the XENEON_POLICY_PATH test seam (core/src/policy.rs) and a loopback
# HTTP sink as the egress observation channel. Four launches over the same
# seed (an httpjson tile polling the sink every 2 s + a Focus tile one step
# from a natural completion — the proven save trigger):
#
#   1. CONTROL (no policy)     — the sink IS hit and the config IS rewritten.
#      Establishes both observation channels; every later "zero" is
#      meaningful only because this run proves the same seed produces
#      non-zero without a policy.
#   2. FORCED PRESET           — force_preset=system-monitor: the user's
#      layout is replaced for the session (its httpjson tile never runs →
#      zero sink hits) and the user's config.toml is NOT overwritten
#      (byte-identical afterwards; the Focus trigger that persisted in run 1
#      persists nothing under the lock).
#   3. NET_OFFLINE PIN         — net_offline=true, no forced preset: the
#      user's layout IS live (the Focus trigger persists, same as control)
#      but the sink gets ZERO hits — the kill switch dominates while the
#      session runs normally.
#   4. PIN vs CONFIG EDIT      — persisted appearance.netOffline is forced
#      to false between launches (the "lift it from disk" attack); the
#      relaunch under the same policy still produces zero hits. Run 1
#      already proved netOffline=false without a policy DOES reach the sink,
#      so the edit is a genuine lift attempt and only the policy blocks it.
#
# Honest limits: "the forced layout is active" is observed via its behavior
# (policy-applied log + the user's widgets demonstrably not running), not via
# a screenshot; the session's rendered pixels are out of scope here.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/rt_common.sh"
rt_require_hub

RT_WORK="$(mktemp -d "${TMPDIR:-/tmp}/xe-rt02.XXXXXX")"
trap 'rt_stop_sink; rm -rf "$RT_WORK"' EXIT
fail=0

rt_start_sink "$RT_WORK" || exit 1
echo "Loopback sink on 127.0.0.1:$RT_SINK_PORT"

printf 'policy_version = 1\nforce_preset = "system-monitor"\n' > "$RT_WORK/policy-forced.toml"
printf 'policy_version = 1\nnet_offline = true\n'              > "$RT_WORK/policy-pin.toml"

TODAY="$(date +%F)"
seed() { # $1 = config dir
    python3 "$HERE/seed_config.py" "$1" >/dev/null <<EOF
{"version":1,"appearance":{"mode":"dark","accent":"#58A6FF","netOffline":false},
 "settings":{"http-1":{"url":"http://127.0.0.1:$RT_SINK_PORT/metric","jsonPath":"value","pollSec":2,"mode":"value"},
             "focus-1":{"preset":"classic","phase":"work","running":true,"endEpoch":1600000000000,"pausedRemaining":1500,"doneToday":3,"day":"$TODAY","points":0,"dailyGoal":4,"rewardPoints":true,"celebrate":true,"autoStartBreak":false}},
 "pages":[{"name":"Main","tiles":[{"id":"http-1","type":"httpjson","size":"1x1"},{"id":"focus-1","type":"focus","size":"1x1.5"}]}]}
EOF
}

focus_done() { rt_json "$(rt_read_config "$1")" 'd["ui_state"]["settings"]["focus-1"]["doneToday"]'; }

# ── 1. CONTROL: no policy — both observation channels must fire ─────────────
echo "Run 1 — control (no policy): egress flows, config persists"
rt_mkroot control; seed "$RT_CFG"
before="$(rt_sink_count)"
rt_run_hub "$RT_ROOT" 8
rt_assert_live "control" "$RT_ROOT" || fail=1
hits=$(( $(rt_sink_count) - before ))
if [ "$hits" -gt 0 ]; then
    echo "  [control] PASS: sink received $hits request(s) — egress channel observable"
else
    echo "  [control] FAIL: sink got no requests — every later zero would be vacuous"
    fail=1
fi
if [ "$(focus_done "$RT_CFG")" = "4" ]; then
    echo "  [control] PASS: config rewritten (focus 3 -> 4) — persistence channel observable"
else
    echo "  [control] FAIL: config not rewritten; persistence channel dead"
    fail=1
fi

# ── 2. FORCED PRESET: layout replaced, user's file untouched ────────────────
echo "Run 2 — force_preset=system-monitor: session layout replaced, config NOT overwritten"
rt_mkroot forced; seed "$RT_CFG"
cp "$RT_CFG/config.toml" "$RT_WORK/forced-seed.toml"
before="$(rt_sink_count)"
rt_run_hub "$RT_ROOT" 8 XENEON_POLICY_PATH="$RT_WORK/policy-forced.toml"
rt_assert_live "forced" "$RT_ROOT" || fail=1
if grep -aq "Org policy loaded and applied" "$RT_ROOT/hub.log"; then
    echo "  [forced] PASS: policy loaded and applied (hub log)"
else
    echo "  [forced] FAIL: no policy-applied log line"; fail=1
fi
hits=$(( $(rt_sink_count) - before ))
if [ "$hits" -eq 0 ]; then
    echo "  [forced] PASS: 0 sink hits — the user's httpjson tile is not running (layout replaced)"
else
    echo "  [forced] FAIL: $hits sink hit(s) — the user's layout is still live under a forced preset"
    fail=1
fi
if cmp -s "$RT_WORK/forced-seed.toml" "$RT_CFG/config.toml"; then
    echo "  [forced] PASS: config.toml byte-identical — user's saved layout not overwritten"
else
    echo "  [forced] FAIL: config.toml changed under the forced-preset lock"
    fail=1
fi

# ── 3. NET_OFFLINE PIN: user layout live, egress dead ───────────────────────
echo "Run 3 — net_offline pinned: user layout runs, zero egress"
rt_mkroot pin; seed "$RT_CFG"
before="$(rt_sink_count)"
rt_run_hub "$RT_ROOT" 8 XENEON_POLICY_PATH="$RT_WORK/policy-pin.toml"
rt_assert_live "pin" "$RT_ROOT" || fail=1
hits=$(( $(rt_sink_count) - before ))
if [ "$hits" -eq 0 ]; then
    echo "  [pin] PASS: 0 sink hits with the kill switch pinned"
else
    echo "  [pin] FAIL: $hits sink hit(s) leaked past the pinned kill switch"
    fail=1
fi
if [ "$(focus_done "$RT_CFG")" = "4" ]; then
    echo "  [pin] PASS: focus 3 -> 4 persisted — the user layout WAS live (zero hits ≠ dead session)"
else
    echo "  [pin] FAIL: user layout did not run under the pin; the zero-hit assertion is vacuous"
    fail=1
fi

# ── 4. The persisted appearance cannot lift the pin ─────────────────────────
echo "Run 4 — edit persisted appearance.netOffline=false, relaunch under the pin"
python3 - "$RT_CFG" <<'EOF'
import json, re, sys, tomllib
cfg = sys.argv[1] + "/config.toml"
with open(cfg, "rb") as f:
    ui = json.loads(tomllib.load(f)["ui_state"])
ui.setdefault("appearance", {})["netOffline"] = False   # the lift attempt
ser = json.dumps(ui, separators=(",", ":"))
assert "'" not in ser
with open(cfg) as f: text = f.read()
with open(cfg, "w") as f:
    f.write(re.sub(r"^ui_state = '.*'$", "ui_state = '%s'" % ser, text, count=1, flags=re.M))
print("edited: appearance.netOffline = false")
EOF
before="$(rt_sink_count)"
rt_run_hub "$RT_ROOT" 8 XENEON_POLICY_PATH="$RT_WORK/policy-pin.toml"
rt_assert_live "lift" "$RT_ROOT" || fail=1
hits=$(( $(rt_sink_count) - before ))
if [ "$hits" -eq 0 ]; then
    echo "  [lift] PASS: still 0 sink hits — persisted config cannot lift the org pin"
else
    echo "  [lift] FAIL: $hits sink hit(s) — a config edit lifted the pinned kill switch"
    fail=1
fi

echo
if [ "$fail" -ne 0 ]; then echo "RESULT: FAILURE"; exit 1; fi
echo "RESULT: SUCCESS — forced preset preserves the user's file; net_offline pin survives config edits"
