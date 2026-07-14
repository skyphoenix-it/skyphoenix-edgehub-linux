#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Lint: every WidgetCatalog type must have a bundled, registered icon.
#
# The add-widget picker renders `AppIcon { name: modelData.type }`
# (ui/qml/Dashboard.qml), so an icon is resolved by the widget's TYPE — a type
# with no `assets/icons/<type>.svg` shows a BLANK tile in the picker. Nothing
# else catches this: tst_appicon.qml asserts the derived qrc path string, not
# that the asset exists, and the QML tests run against the source tree with no
# qrc, so a missing SVG is invisible to the whole suite. It only ever showed up
# as a `QML QQuickImage: Cannot open: qrc:/icons/<type>.svg` warning in a
# real-device grab (that is how httpjson/kpi were caught in E1).
#
# Checks, per type: the SVG exists on disk AND is registered in assets/icons.qrc.
# ─────────────────────────────────────────────────────────────────────────────
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CATALOG="$ROOT/ui/qml/WidgetCatalog.qml"
ICON_DIR="$ROOT/assets/icons"
ICON_QRC="$ROOT/assets/icons.qrc"

violations=0
checked=0

# `type: "<name>"` entries in the catalog's items list.
types=$(grep -oE '\{ *type: *"[a-z0-9]+"' "$CATALOG" | sed -E 's/.*type: *"([a-z0-9]+)".*/\1/' | sort -u)
[ -n "$types" ] || { echo "  ✗ no widget types parsed from $CATALOG — the lint would pass vacuously"; exit 1; }

for t in $types; do
    checked=$((checked + 1))
    if [ ! -f "$ICON_DIR/$t.svg" ]; then
        echo "  ✗ widget type '$t' has no icon: assets/icons/$t.svg (picker would render blank)"
        violations=$((violations + 1))
        continue
    fi
    if ! grep -qF "\"$t.svg\"" "$ICON_QRC"; then
        echo "  ✗ assets/icons/$t.svg exists but is NOT registered in assets/icons.qrc (absent at runtime)"
        violations=$((violations + 1))
    fi
done

if [ "$violations" -ne 0 ]; then
    echo "LINT FAILED: $violations widget icon violation(s) across $checked types"
    exit 1
fi
echo "OK: all $checked widget types have a bundled, registered icon"
