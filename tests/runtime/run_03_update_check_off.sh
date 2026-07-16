#!/usr/bin/env bash
# Scenario 03 — the update check is OFF by default (E10 privacy contract).
#
# Launches the real hub on a default-shaped config (no updateCheck key
# anywhere) and lets it idle well past the only startup-time check window
# (UpdateChecker fires immediately when enabled; the next trigger is a 24 h
# timer, honestly out of scope for a test).
#
# Assertions, strongest available first:
#   REAL  — packaging/ci/no-egress.sh default: the hub runs in a network
#           namespace under strace with a DNS/TCP sink, and the attestation
#           asserts ZERO egress of any kind. Run when the environment can
#           (unprivileged user namespaces + strace); its verdict is binding.
#   PROXY — always run: after a real save round-trip, the persisted
#           appearance carries no enabled updateCheck key, and the hub log
#           shows no update-check activity (no releases URL, no check
#           failure). This is the honest local proxy — this scenario cannot
#           observe sockets without the namespace, and says so.
#
# The script prints which of the two actually ran.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/rt_common.sh"
rt_require_hub

RT_WORK="$(mktemp -d "${TMPDIR:-/tmp}/xe-rt03.XXXXXX")"
trap 'rm -rf "$RT_WORK"' EXIT
fail=0

# ── PROXY: default config, idle past the startup window, inspect what persists ──
echo "Proxy assertion — persisted config and hub log after an idle run"
rt_mkroot idle
TODAY="$(date +%F)"
# Default-shaped doc + the Focus save trigger, so the post-run config.toml is
# HUB-AUTHORED (a doc the hub itself serialized), not just our seed echoed back.
python3 "$HERE/seed_config.py" "$RT_CFG" >/dev/null <<EOF
{"version":1,"appearance":{"mode":"dark","accent":"#58A6FF"},
 "settings":{"focus-1":{"preset":"classic","phase":"work","running":true,"endEpoch":1600000000000,"pausedRemaining":1500,"doneToday":0,"day":"$TODAY","points":0,"dailyGoal":9,"rewardPoints":false,"celebrate":false,"autoStartBonus":false}},
 "pages":[{"name":"Main","tiles":[{"id":"clock-1","type":"clock","size":"1x1"},{"id":"focus-1","type":"focus","size":"1x1"}]}]}
EOF
rt_run_hub "$RT_ROOT" 10
rt_assert_live "idle" "$RT_ROOT" || fail=1
if ! grep -aq "Configuration saved" "$RT_ROOT/hub.log"; then
    echo "  [idle] FAIL: no save happened — the persisted-key assertion would be vacuous"
    fail=1
else
    upd="$(rt_json "$(rt_read_config "$RT_CFG")" 'd["ui_state"]["appearance"].get("updateCheck")')"
    if [ "$upd" = "True" ] || [ "$upd" = "true" ]; then
        echo "  [idle] FAIL: hub persisted appearance.updateCheck=$upd on a default config"
        fail=1
    else
        echo "  [idle] PASS: no enabled updateCheck key in the hub-authored config (got: $upd)"
    fi
fi
if grep -aqE "api\.github\.com|releases/latest|Check failed" "$RT_ROOT/hub.log"; then
    echo "  [idle] FAIL: hub log shows update-check activity on a default config:"
    grep -aE "api\.github\.com|releases/latest|Check failed" "$RT_ROOT/hub.log" | sed 's/^/    /'
    fail=1
else
    echo "  [idle] PASS: no update-check activity in the hub log"
fi

# ── REAL: the no-egress attestation, when this environment can run it ────────
NOEGRESS="$RT_PROJECT_DIR/packaging/ci/no-egress.sh"
real_ran=no
if [ -x "$NOEGRESS" ] || [ -f "$NOEGRESS" ]; then
    if command -v strace >/dev/null 2>&1 && unshare --net --mount --map-root-user true 2>/dev/null; then
        echo "Real assertion — packaging/ci/no-egress.sh default (netns + strace + DNS sink)"
        if XENEON_HUB="$HUB" XENEON_EGRESS_SECS="${XENEON_EGRESS_SECS:-10}" bash "$NOEGRESS" default > "$RT_WORK/no-egress.out" 2>&1; then
            real_ran=yes
            grep -E "^✓|ATTESTATION" "$RT_WORK/no-egress.out" | sed 's/^/  /'
        else
            rc=$?
            if [ "$rc" -eq 77 ]; then
                echo "  no-egress.sh skipped (77) — proxy assertion stands alone"
            else
                echo "  FAIL: the no-egress attestation failed (rc=$rc):"
                tail -25 "$RT_WORK/no-egress.out" | sed 's/^/    /'
                fail=1
            fi
        fi
    else
        echo "Real assertion unavailable (no strace or no unprivileged user namespaces) — proxy only"
    fi
else
    echo "Real assertion unavailable (packaging/ci/no-egress.sh not found) — proxy only"
fi

echo
echo "Assertion level: proxy=yes real-no-egress=$real_ran"
if [ "$fail" -ne 0 ]; then echo "RESULT: FAILURE"; exit 1; fi
echo "RESULT: SUCCESS — update check stays off and silent on a default config"
