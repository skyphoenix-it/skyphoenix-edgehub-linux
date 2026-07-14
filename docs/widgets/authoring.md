# Creating a Widget

This is the practical, end-to-end guide to adding a new widget to the Xeneon Edge
Hub. A widget is a single self-contained QML file plus a few one-line
registrations. If you can write basic QML, you can ship a widget in ~20 minutes.

> **Fast path:** run `./scripts/new-widget.sh` — it scaffolds the file, wires the
> resource bundles, drops a placeholder icon, and prints the two snippets you
> paste by hand. The rest of this doc explains what it generates and why.

---

## The mental model

Every widget:

- Has its root be a **`WidgetChrome`** — the shared glass card that draws the
  header (icon + title), the frosted surface, and the accent glow. You only write
  the *content*.
- Is registered once in **`WidgetCatalog.qml`** (the registry) and reused
  everywhere: the dashboard grid, the full-screen expanded view, the add-widget
  picker, and the Manager's WYSIWYG clone.
- Reads live per-instance settings from the **store** and writes them back, so a
  tile and its expanded/config view share one live state.
- Declares an optional **config schema** so the on-device config view and the
  desktop Manager both render a professional form for it — with descriptions and
  real options. **Every option you declare must actually be honoured** by the
  widget (no decorative toggles).

The same widget file runs in two hosts (the hub and the Manager). Don't assume a
running hub, network, or specific screen — degrade gracefully.

---

## Injected properties (the contract)

The host injects these onto your root object at load time. Declare the ones you
use:

| Property | Type | Meaning |
|---|---|---|
| `metrics` | `var` | Parsed system metrics JSON (CPU/GPU/RAM/net/disk). Updates ~2 s. |
| `expanded` | `bool` | `true` in the full-screen view; drive richer layouts off this. |
| `active` | `bool` | `false` when a background tile should pause timers (an overlay is open / edit mode). Gate `Timer { running: w.active }`. |
| `store` | `var` | The DashboardStore — read/write per-instance settings. |
| `instanceId` | `string` | This tile's unique id; the key into settings. |
| `tick` | `int` | *(optional)* a once-per-second counter — declare it if you show time. |
| `titleOverride` | `string` | *(optional, on WidgetChrome)* user's custom title; already handled by WidgetChrome. |

`theme` and (for media) `media` resolve from context — reference them
unqualified, e.g. `theme.accent`. Don't import or instantiate them.

---

## Reading & writing settings (live config)

Use this exact pattern so edits from the config view apply instantly:

```qml
// Live per-instance config. store.revision makes it re-read on every change.
readonly property var cfg: {
    var _ = store ? store.revision : 0
    return (store && instanceId) ? store.settingsFor(instanceId) : ({})
}
// One readonly helper per option, with the SAME default as the schema `dflt`.
readonly property bool showThing: cfg.showThing !== undefined ? cfg.showThing : true
```

Write a value back with `store.setSetting(instanceId, "key", value)` (or
`store.patchSettings(instanceId, { a: 1, b: 2 })` for several at once). Never
mutate `cfg` directly.

---

## A complete minimal widget

`ui/qml/widgets/HelloWidget.qml`:

```qml
import QtQuick
import QtQuick.Layouts

// One-line description of what this widget does.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Hello"; iconName: "hello"; accentColor: theme.catInfo
    big: expanded                       // WidgetChrome renders bigger content when true

    // Live config
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? store.settingsFor(instanceId) : ({})
    }
    readonly property string who: cfg.who !== undefined ? cfg.who : "world"

    // Content goes in the default slot (below the header).
    ColumnLayout {
        anchors.fill: parent
        Text {
            Layout.alignment: Qt.AlignCenter
            text: "Hello, " + w.who + "!"
            color: theme.textPrimary
            font.pixelSize: w.expanded ? 48 : 20
            font.family: theme.fontDisplay
        }
    }
}
```

That already renders as a proper glass tile, expands full-screen, and shows up in
the picker — once you register it.

---

## Registration checklist

For a widget of type `hello` (file `HelloWidget.qml`):

1. **Catalog entry** — add to the `items` array in `ui/qml/WidgetCatalog.qml`:
   ```js
   { type: "hello", title: "Hello", category: "Info",
     source: "qrc:/qml/HelloWidget.qml", defaults: { who: "world" } },
   ```
   `defaults` seeds a fresh instance's settings. `category` groups it in the picker
   (reuse an existing one: System / Time / Focus / Media / Data / Info).

2. **Description** — add to the `_desc` map in the same file (shown in the
   expanded header):
   ```js
   "hello": "Greets someone. Set the name in config.",
   ```

3. **Icon** — drop a white-filled SVG at `assets/icons/hello.svg` (the file name
   **must equal the type**) and add one line to `assets/icons.qrc`:
   ```xml
   <file alias="hello.svg">icons/hello.svg</file>
   ```
   Icons are [Phosphor](https://phosphoricons.com) SVGs normalised to `fill="#FFFFFF"`
   (AppIcon tints them). Keep the `viewBox="0 0 256 256"`. A stroked glyph
   (`fill="none" stroke="#FFFFFF" stroke-width="16"`) tints identically — match the
   existing weight either way.

   The picker resolves the icon **by type** (`AppIcon { name: modelData.type }`), so
   a missing SVG renders a blank tile. The QML suite cannot see this (it runs against
   the source tree, with no qrc), so `scripts/check_widget_icons.sh` gates it: every
   catalog type must have an SVG on disk **and** a line in `assets/icons.qrc`.

4. **Bundle for the hub** — add to `ui/qml.qrc`:
   ```xml
   <file alias="qml/HelloWidget.qml">qml/widgets/HelloWidget.qml</file>
   ```

5. **Bundle for the Manager** — add to `manager/manager.qrc`:
   ```xml
   <file alias="HelloWidget.qml">../ui/qml/widgets/HelloWidget.qml</file>
   ```

6. **Config schema** *(optional but recommended)* — add a `case` in
   `ui/qml/WidgetConfigSchema.qml` so the config view shows real options:
   ```js
   case "hello": return { sections: [
       { title: "Greeting", cols: 1, fields: [
           { key: "who", label: "Name", type: "text", placeholder: "world", dflt: "world" } ] },
       titleSection("Hello"),
       about("Greets someone. Set the name in config.") ] }
   ```
   Field types: `text | textarea | number | slider | toggle | segmented | date |
   hour | tasks | action | info`. Fields may carry a `help` string. If you add no
   `case`, the widget still works and gets a General (custom title) section by
   default. **Whatever options you declare, read them via `cfg` and honour them.**

7. **Networking** *(only if the widget fetches something)* — **never construct an
   `XMLHttpRequest`.** All egress goes through the `NetHub` gate, which owns the
   global offline switch, the host allowlist and the request counters — the single
   audited choke point behind the "no telemetry / local-only" claim:
   ```qml
   property var netHub: null          // injected by Dashboard (one app-global hub)
   NetHub { id: _fallbackHub }        // fallback keeps the widget standalone in tests
   function _hub() { return netHub ? netHub : _fallbackHub }

   _hub().request({ url: w.url, headers: h, xhrFactory: w.xhrFactory,
                    onDone: function (status, body) { … },
                    onError: function (reason) { … } })   // offline|blocked|timeout|http <n>
   ```
   `scripts/check_no_raw_xhr.sh` fails the build if a raw XHR appears outside the
   gate. Poll results must be mirrored into **ephemeral** store keys
   (`DashboardStore._ephemeralKeys`) or every poll rewrites `config.toml` (flash
   wear + a save race with the Manager). See `HttpJsonWidget.qml` for the full shape.

> ⚠️ **The #1 gotcha:** forgetting steps 4/5. The QML test suite loads widgets from
> the source tree and will pass, but the real app loads from the compiled `qrc`
> and fails at runtime with `HelloWidget is not a type`. Always rebuild and launch
> the actual hub to verify. The same blind spot hides missing icons (step 3) — both
> are now gated by lints in `run_all_tests.sh`, but a real grab is still the only
> thing that proves it *looks* right.

---

## Available data & helpers

- **System metrics** (`metrics.*`): `cpu_usage_percent`, `cpu_temp_celsius`,
  `cpu_core_count`, `ram_usage_percent`, `ram_total_bytes`, `ram_used_bytes`,
  `gpu_usage_percent`, `gpu_temp_celsius`, `net_rx_bytes_per_sec`,
  `net_tx_bytes_per_sec`, `disk_total_bytes`, `disk_used_bytes`,
  `disk_usage_percent`. That's the whole set — don't declare options the metrics
  can't back (e.g. per-interface network or an arbitrary disk mount).
- **Network / the internet**: use `XMLHttpRequest` directly (see `WeatherWidget`
  for a debounced fetch + a config `action` that geocodes). Handle offline.
- **Reusable UI**: `MetricGauge` (ring + centre value + sparkline), `RingProgress`,
  `Sparkline`, `PillButton`, `SegmentedControl`, `AppIcon`. Read an existing
  widget in the same family before writing a new one.
- **Design tokens**: colours (`theme.accent`, `theme.catSystem/Info/Gaming/…`),
  spacing (`theme.spacingSm/Md/Lg`), radii, touch sizes (`theme.touchPrimary`
  ≈ 76 px — keep tap targets big), fonts (`theme.fontDisplay/fontMono`), motion
  (`theme.motionFast`). Never hard-code colours or sizes.

---

## Testing

- `./scripts/run_ui_tests.sh` runs the offscreen QML suite. `tst_smoke.qml`
  **auto-covers every catalog widget** across nominal/zero/saturated/empty
  settings × compact/expanded — so once you register your widget it's smoke-tested
  for free. Add a `tst_<type>.qml` if it has real interaction/logic.
- Build + launch the real hub and confirm zero `is not a type` lines:
  `QT_QPA_PLATFORM=offscreen ./build/xeneon-edge-hub --windowed`
- Preview the config view on-device without tapping:
  `XENEON_EXPAND=hello ./build/xeneon-edge-hub` (and in the Manager:
  `XENEON_CFG=hello`).
- Screenshot the real Edge to catch anything headless misses (see
  `docs/development/setup.md`).

---

## Style rules (so widgets feel like one product)

- Root is always `WidgetChrome`; content in the default slot; `big: expanded`.
- Large, tappable controls; no tiny hit areas. Use `PillButton` / `SegmentedControl`.
- Gate timers on `active`. Keep idle CPU near zero (paint-once Canvas + GPU
  transforms, not per-frame repaints).
- Professional monochrome iconography via `AppIcon`; no emoji as chrome.
- Degrade gracefully with no data / no network.

See also: [architecture](../architecture/) · [widget user guide](user-guide.md).
