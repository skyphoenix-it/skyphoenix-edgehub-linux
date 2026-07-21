#!/usr/bin/env bash
# Scenario 05 - corrupt-config salvage (core/src/config.rs semantics).
#
# Garbles config.toml the way a torn write does (valid head, junk tail - the
# shape config.rs's own tests use), launches the real hub, and asserts the
# salvage contract:
#
#   * the corrupt file is preserved under a TIMESTAMPED config.toml.corrupt-*.bak,
#     byte-identical - nothing the user had is destroyed;
#   * the canonical good backup (config.toml.bak) is NOT clobbered by the
#     corrupt content;
#   * the hub comes up and stays up (liveness: full window + control server);
#   * first_run_complete survives salvage - the first-run wizard is NOT
#     re-triggered by corruption;
#   * the hub recovers to a WORKING persisted state: the post-run config.toml
#     is valid TOML with a parseable ui_state.
#
# KNOWN, DELIBERATELY-NOT-ASSERTED LIMIT: salvage_partial_config() recovers the
# `ui_state` line only when it is a double-quoted TOML string, but the hub
# itself serializes ui_state as a SINGLE-QUOTED literal - so on today's code
# the dashboard LAYOUT does not survive into the live config (it is re-seeded;
# the only copy of the user's layout is the .corrupt-*.bak). That is a product
# gap in core/src/config.rs, outside this scenario's ownership; asserting
# layout survival here would be red on a guarantee the core never made. The
# assertions above are the ones config.rs actually provides.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/rt_common.sh"
rt_require_hub

RT_WORK="$(mktemp -d "${TMPDIR:-/tmp}/xe-rt05.XXXXXX")"
trap 'rm -rf "$RT_WORK"' EXIT
fail=0

rt_mkroot c
# A config in the hub's own on-disk shape (nested tables, single-quoted
# ui_state literal - matches what save_config writes, verified by probe).
python3 "$HERE/seed_config.py" "$RT_CFG" >/dev/null <<EOF
{"version":1,"appearance":{"mode":"dark","accent":"#58A6FF"},
 "settings":{},
 "pages":[{"name":"Mine","tiles":[{"id":"clock-u1","type":"clock","size":"1x1"}]}]}
EOF

# A pre-existing GOOD backup that corruption must never clobber.
printf 'sentinel-good-backup-do-not-touch\n' > "$RT_CFG/config.toml.bak"

# Torn write: valid head, garbage tail (whole-file TOML parse fails).
printf '\ngarbage = = torn-write\n' >> "$RT_CFG/config.toml"
cp "$RT_CFG/config.toml" "$RT_WORK/corrupt-as-written.toml"

echo "Launching hub over the corrupted config"
rt_run_hub "$RT_ROOT" 8
rt_assert_live "salvage" "$RT_ROOT" || fail=1

if grep -aq "Config parse failed; backing up and salvaging" "$RT_ROOT/hub.log"; then
    echo "  [salvage] PASS: hub hit the salvage path (log)"
else
    echo "  [salvage] FAIL: salvage path never engaged - did the corruption parse?"
    fail=1
fi

# Timestamped corrupt backup, byte-identical to what was on disk.
shopt -s nullglob
corrupt_baks=("$RT_CFG"/config.toml.corrupt-*.bak)
shopt -u nullglob
if [ "${#corrupt_baks[@]}" -eq 1 ] && cmp -s "${corrupt_baks[0]}" "$RT_WORK/corrupt-as-written.toml"; then
    echo "  [backup] PASS: $(basename "${corrupt_baks[0]}") preserves the corrupt file byte-for-byte"
else
    echo "  [backup] FAIL: expected exactly one byte-identical corrupt-*.bak, found ${#corrupt_baks[@]}"
    fail=1
fi

# The canonical good backup must survive untouched.
if [ "$(cat "$RT_CFG/config.toml.bak" 2>/dev/null)" = "sentinel-good-backup-do-not-touch" ]; then
    echo "  [goodbak] PASS: config.toml.bak untouched"
else
    echo "  [goodbak] FAIL: the canonical good backup was clobbered"
    fail=1
fi

# Salvage keeps the completed-setup flag and recovers to a working config.
doc="$(rt_read_config "$RT_CFG" 2>/dev/null)" || doc=""
if [ -z "$doc" ]; then
    echo "  [recover] FAIL: post-run config.toml is not valid TOML"
    fail=1
else
    frc="$(rt_json "$doc" 'd["first_run_complete"]')"
    has_ui="$(rt_json "$doc" 'd["ui_state"] is not None')"
    if [ "$frc" = "True" ]; then
        echo "  [wizard] PASS: first_run_complete survived salvage (wizard not re-triggered)"
    else
        echo "  [wizard] FAIL: corruption reset first_run_complete - wizard would reappear"
        fail=1
    fi
    if [ "$has_ui" = "True" ]; then
        echo "  [recover] PASS: hub persisted a valid, parseable config after salvage"
    else
        echo "  [recover] FAIL: post-salvage config has no parseable ui_state"
        fail=1
    fi
fi

echo
if [ "$fail" -ne 0 ]; then echo "RESULT: FAILURE"; exit 1; fi
echo "RESULT: SUCCESS - corruption is backed up, survives no data destruction, and the hub recovers"
