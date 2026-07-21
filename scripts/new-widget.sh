#!/usr/bin/env bash
# Scaffold a new widget: creates the QML file, drops a placeholder icon, wires the
# resource bundles (ui/qml.qrc, manager/manager.qrc, assets/icons.qrc), and prints
# the two snippets you paste by hand (catalog entry + config schema).
#
# Usage:   ./scripts/new-widget.sh <type> "<Title>" [Category]
# Example: ./scripts/new-widget.sh stocks "Stock Ticker" Info
#
# See docs/widgets/authoring.md for the full guide.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TYPE="${1:-}"
TITLE="${2:-}"
CATEGORY="${3:-Info}"

if [[ -z "$TYPE" || -z "$TITLE" ]]; then
    echo "Usage: $0 <type> \"<Title>\" [Category]" >&2
    echo "  <type>     lowercase id, e.g. stocks   (also the icon file name)" >&2
    echo "  <Title>    display name, e.g. \"Stock Ticker\"" >&2
    echo "  [Category] picker group (default: Info) - System/Time/Focus/Media/Info" >&2
    exit 1
fi
if ! [[ "$TYPE" =~ ^[a-z][a-z0-9]*$ ]]; then
    echo "ERROR: <type> must be lowercase letters/digits, starting with a letter." >&2
    exit 1
fi

# CamelCase the type for the file name: stocks -> Stocks, my_thing not allowed.
CAMEL="$(printf '%s' "$TYPE" | sed -E 's/(^|_)([a-z])/\U\2/g')"
QML="ui/qml/widgets/${CAMEL}Widget.qml"
ICON="assets/icons/${TYPE}.svg"

# Pick an accent colour token by category.
case "$CATEGORY" in
    System)  ACCENT="theme.catSystem" ;;
    Time)    ACCENT="theme.catSystem" ;;
    Focus)   ACCENT="theme.catProductivity" ;;
    Media)   ACCENT="theme.catEntertainment" ;;
    Gaming)  ACCENT="theme.catGaming" ;;
    *)       ACCENT="theme.catInfo" ;;
esac

if [[ -e "$QML" ]]; then echo "ERROR: $QML already exists." >&2; exit 1; fi

# --- 1. Widget QML from template ---
cat > "$QML" <<QMLEOF
import QtQuick
import QtQuick.Layouts

// ${TITLE} - TODO: one-line description of what this widget does.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "${TITLE}"; iconName: "${TYPE}"; accentColor: ${ACCENT}

    // Live per-instance config (see docs/widgets/authoring.md).
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? store.settingsFor(instanceId) : ({})
    }
    // Example option - keep the default in sync with the schema \`dflt\`:
    readonly property string label: cfg.label !== undefined ? cfg.label : "${TITLE}"

    ColumnLayout {
        anchors.fill: parent
        Text {
            Layout.alignment: Qt.AlignCenter
            text: w.label
            color: theme.textPrimary
            font.pixelSize: w.expanded ? 40 : 20
            font.family: theme.fontDisplay
        }
    }
}
QMLEOF
echo "created  $QML"

# --- 2. Placeholder icon (replace with a real Phosphor SVG) ---
if [[ ! -e "$ICON" ]]; then
cat > "$ICON" <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="#FFFFFF"><path d="M208,32H48A16,16,0,0,0,32,48V208a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V48A16,16,0,0,0,208,32Zm0,176H48V48H208V208ZM140,128a12,12,0,1,1-12-12A12,12,0,0,1,140,128Z"/></svg>
SVGEOF
echo "created  $ICON  (placeholder - replace with a real icon from phosphoricons.com)"
fi

# --- 3. Wire the resource bundles ---
insert_before() { # file, marker-regex, line-to-insert
    local file="$1" marker="$2" line="$3"
    if grep -qF "$line" "$file"; then return 0; fi
    # Insert the line just before the first matching marker line.
    awk -v m="$marker" -v ins="$line" '
        !done && $0 ~ m { print ins; done=1 }
        { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

insert_before "ui/qml.qrc" "</qresource>" \
    "        <file alias=\"qml/${CAMEL}Widget.qml\">qml/widgets/${CAMEL}Widget.qml</file>"
echo "wired    ui/qml.qrc"

insert_before "manager/manager.qrc" "</qresource>" \
    "        <file alias=\"${CAMEL}Widget.qml\">../ui/qml/widgets/${CAMEL}Widget.qml</file>"
echo "wired    manager/manager.qrc"

insert_before "assets/icons.qrc" "</qresource>" \
    "        <file alias=\"${TYPE}.svg\">icons/${TYPE}.svg</file>"
echo "wired    assets/icons.qrc"

# --- 4. Print the two manual snippets ---
cat <<MSG

────────────────────────────────────────────────────────────────────────────
Almost done. Paste these two snippets by hand (they live in JS, not easily
auto-edited safely):

1) ui/qml/WidgetCatalog.qml - add to the \`items\` array:

        { type: "${TYPE}", title: "${TITLE}", category: "${CATEGORY}",
          source: "qrc:/qml/${CAMEL}Widget.qml", defaults: { label: "${TITLE}" } },

   ...and to the \`_desc\` map:

        "${TYPE}": "TODO: one-line description shown in the expanded header.",

2) ui/qml/WidgetConfigSchema.qml - add a case in schemaFor() (optional but nice):

        case "${TYPE}": return { sections: [
            { title: "Settings", cols: 1, fields: [
                { key: "label", label: "Label", type: "text", placeholder: "${TITLE}", dflt: "${TITLE}" } ] },
            titleSection("${TITLE}"),
            about("TODO: describe the widget.") ] }

Then:
    ./scripts/build.sh release          # rebuild (qrc is compiled in)
    ./scripts/run_ui_tests.sh           # smoke-tests your widget automatically
    XENEON_EXPAND=${TYPE} ./build/xeneon-edge-hub   # preview its config view

Replace the placeholder icon at ${ICON} with a real one, and flesh out the
widget body + honour every option you declared. Full guide: docs/widgets/authoring.md
────────────────────────────────────────────────────────────────────────────
MSG
