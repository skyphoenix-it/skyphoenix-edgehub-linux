#!/usr/bin/env bash
# Scenario 04 — secret REFERENCES never persist as VALUES (E7 Phase A).
#
# Seeds an httpjson tile whose authToken is the reference "${env:XENEON_RT_SECRET}"
# and points it at a loopback sink; launches the real hub with the variable set
# to a run-unique value. Asserts, in order of proof:
#
#   1. NON-VACUOUS: the sink received "Authorization: Bearer <value>" — the
#      ref really was resolved and used this run (a scenario that never
#      resolves the secret could not catch a leak).
#   2. The hub REWROTE config.toml this run (Focus save trigger), so the
#      persisted doc is hub-authored — the exact bytes the store serializes.
#   3. The rewritten config still carries the REFERENCE string, verbatim.
#   4. The resolved VALUE appears NOWHERE in the config dir — config.toml,
#      backups, temp files, anything (recursive grep).
#
# Honest limit: this proves the value never reaches DISK through the store's
# save path in this session; it does not (cannot) prove anything about process
# memory, and the sink obviously sees the value — sending it is the feature.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/rt_common.sh"
rt_require_hub

RT_WORK="$(mktemp -d "${TMPDIR:-/tmp}/xe-rt04.XXXXXX")"
trap 'rt_stop_sink; rm -rf "$RT_WORK"' EXIT
fail=0

rt_start_sink "$RT_WORK" || exit 1
echo "Loopback sink on 127.0.0.1:$RT_SINK_PORT"

SECRET="rt-secret-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
REF='${env:XENEON_RT_SECRET}'
TODAY="$(date +%F)"

rt_mkroot s
python3 "$HERE/seed_config.py" "$RT_CFG" >/dev/null <<EOF
{"version":1,"appearance":{"mode":"dark","accent":"#58A6FF"},
 "settings":{"http-1":{"url":"http://127.0.0.1:$RT_SINK_PORT/metric","jsonPath":"value","pollSec":2,"mode":"value","authToken":"\${env:XENEON_RT_SECRET}"},
             "focus-1":{"preset":"classic","phase":"work","running":true,"endEpoch":1600000000000,"pausedRemaining":1500,"doneToday":0,"day":"$TODAY","points":0,"dailyGoal":9,"rewardPoints":false,"celebrate":false,"autoStartBreak":false}},
 "pages":[{"name":"Main","tiles":[{"id":"http-1","type":"httpjson","size":"1x1"},{"id":"focus-1","type":"focus","size":"1x1.5"}]}]}
EOF

echo "Launching hub with XENEON_RT_SECRET set (value unique to this run)"
rt_run_hub "$RT_ROOT" 9 XENEON_RT_SECRET="$SECRET"
rt_assert_live "secrets" "$RT_ROOT" || fail=1

# 1. The ref was resolved and USED (otherwise nothing below proves anything).
if grep -q "Bearer $SECRET" "$RT_SINK_LOG"; then
    n="$(grep -c "Bearer $SECRET" "$RT_SINK_LOG")"
    echo "  [resolve] PASS: sink saw the resolved Bearer token on $n request(s)"
else
    echo "  [resolve] FAIL: sink never saw the resolved token — the run is vacuous"
    sed 's/^/    sink: /' "$RT_SINK_LOG"
    fail=1
fi

# 2. The persisted doc is hub-authored (a real save round-trip happened).
if grep -aq "Configuration saved" "$RT_ROOT/hub.log"; then
    echo "  [rewrite] PASS: hub rewrote config.toml this run"
else
    echo "  [rewrite] FAIL: config.toml was never rewritten — persistence assertions are vacuous"
    fail=1
fi

# 3. The reference survives the round-trip, verbatim.
if grep -qF "$REF" "$RT_CFG/config.toml"; then
    echo "  [ref] PASS: persisted config still carries the reference $REF"
else
    echo "  [ref] FAIL: the reference is gone from the persisted config"
    fail=1
fi

# 4. The value is nowhere on disk under the config root.
if grep -rqF "$SECRET" "$RT_ROOT/config"; then
    echo "  [value] FAIL: the RESOLVED SECRET is on disk:"
    grep -rlF "$SECRET" "$RT_ROOT/config" | sed 's/^/    /'
    fail=1
else
    echo "  [value] PASS: resolved value appears nowhere under the config dir"
fi

echo
if [ "$fail" -ne 0 ]; then echo "RESULT: FAILURE"; exit 1; fi
echo "RESULT: SUCCESS — the stored token stays a reference; the resolved value never touches disk"
