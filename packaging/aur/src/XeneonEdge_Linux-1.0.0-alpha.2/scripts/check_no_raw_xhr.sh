#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Lint: raw XMLHttpRequest may appear ONLY in the NetHub egress gate.
#
# Every network widget must route through NetHub.request(), so all outbound
# traffic has a single audited choke point (the basis of the "no telemetry /
# local-only" claim and the enterprise egress attestation). This lint fails the
# moment a new widget constructs its own XHR.
#
# There is no exemption list: E8 migrated the last holdouts (Weather, Calendar,
# the Manager's config dialog) onto the gate. Do not add one — an exception here
# is a hole in the claim, not a lint detail.
# ─────────────────────────────────────────────────────────────────────────────
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GATE="ui/qml/widgets/NetHub.qml"

violations=0
while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    [ "$rel" = "$GATE" ] && continue
    echo "  ✗ raw XMLHttpRequest outside NetHub: $rel  (route it through NetHub.request)"
    violations=$((violations + 1))
done < <(grep -rlE 'new[[:space:]]+XMLHttpRequest' "$ROOT/ui" "$ROOT/manager" 2>/dev/null | grep '\.qml$')

# The gate must still own exactly one construction site.
if ! grep -qE 'new[[:space:]]+XMLHttpRequest' "$ROOT/$GATE"; then
    echo "  ✗ $GATE no longer constructs the XHR — the gate is the one allowed site"
    violations=$((violations + 1))
fi

if [ "$violations" -ne 0 ]; then
    echo "LINT FAILED: $violations raw-XHR violation(s)"
    exit 1
fi
echo "OK: raw XMLHttpRequest confined to NetHub"
