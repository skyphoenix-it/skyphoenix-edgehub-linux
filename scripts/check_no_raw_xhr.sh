#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Lint: raw XMLHttpRequest may appear ONLY in the NetHub egress gate.
#
# Every network widget must route through NetHub.request(), so all outbound
# traffic has a single audited choke point (the basis of the "no telemetry /
# local-only" claim and the enterprise egress attestation). This lint fails the
# moment a new widget constructs its own XHR.
#
# WeatherWidget/CalendarWidget predate the gate and are temporarily grandfathered
# — they are scheduled to migrate onto NetHub in E8 (egress control / offline
# mode). No NEW file may be added to the grandfather list.
# ─────────────────────────────────────────────────────────────────────────────
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GATE="ui/qml/widgets/NetHub.qml"
GRANDFATHERED="ui/qml/widgets/WeatherWidget.qml ui/qml/widgets/CalendarWidget.qml manager/qml/WidgetConfigDialog.qml"

violations=0
while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    case " $GATE $GRANDFATHERED " in
        *" $rel "*) continue ;;
    esac
    echo "  ✗ raw XMLHttpRequest outside NetHub: $rel  (route it through NetHub.request)"
    violations=$((violations + 1))
done < <(grep -rlE 'new[[:space:]]+XMLHttpRequest' "$ROOT/ui" "$ROOT/manager" 2>/dev/null | grep '\.qml$')

# The gate must still own exactly one construction site.
if ! grep -qE 'new[[:space:]]+XMLHttpRequest' "$ROOT/$GATE"; then
    echo "  ✗ $GATE no longer constructs the XHR — the gate is the one allowed site"
    violations=$((violations + 1))
fi

# Nudge to shrink the grandfather list once Weather/Calendar migrate (E8).
for g in $GRANDFATHERED; do
    if ! grep -qE 'new[[:space:]]+XMLHttpRequest' "$ROOT/$g" 2>/dev/null; then
        echo "  ℹ $g no longer uses a raw XHR — drop it from the grandfather list in this script."
    fi
done

if [ "$violations" -ne 0 ]; then
    echo "LINT FAILED: $violations raw-XHR violation(s)"
    exit 1
fi
echo "OK: raw XMLHttpRequest confined to NetHub (grandfathered pending E8: Weather, Calendar)"
