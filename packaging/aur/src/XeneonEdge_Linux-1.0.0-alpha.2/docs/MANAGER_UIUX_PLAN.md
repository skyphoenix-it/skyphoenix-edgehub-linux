# Manager UI/UX + Theme + Robustness — Fix Plan

**Status:** Awaiting approval · **Created:** 2026-07-13

## Context

The Manager's per-widget config **functionality** is fixed (store-wiring self-binding).
Remaining issues are **graphical**, plus the user wants **more theme options** and **more
robustness**. Two deep read-only analyses (UI/UX+graphical, theme+robustness) produced the
findings below. This plan turns them into scoped, tested work.

**Root cause of ~all graphical bugs:** `manager/src/main.cpp:30` sets
`QQuickStyle::setStyle("Fusion")` but installs **no dark `QPalette`**. Every Qt Quick
control that isn't hand-restyled (Switch, Slider, Button, ScrollBar, Dialog button-boxes/
titles) renders in Fusion's **default light-gray palette** on the dark UI. That's why the
config toggles look like pale default switches. The team hand-rolled `MButton`/`MSwitch`
for the chrome but everything reached via `ConfigField`/dialogs is still raw Fusion.

---

## Phase 1 — Graphical / UI-UX (the "graphical bugs")

**1a. Install a dark QPalette (single highest-ROI fix).** In `manager/src/main.cpp` (and
the hub `app/src/main.cpp` for the on-device config), set a dark `QPalette` on the
`QGuiApplication` (Window/Base/Button/Text/Highlight from the theme tokens) alongside
`setStyle("Fusion")`. Resolves the light-control cluster: config `Switch`, `Slider`,
`Button`, `ScrollBar`, and Dialog `Close/Yes/No` button-boxes at once.

**1b. Restyle the remaining shared controls to tokens** (palette gets them close; finish
the shape so they match `MSwitch`/`MButton`):
- `ConfigField.qml` `toggleC` (:203) → token-styled switch (mirror `MSwitch`, use `f.col`).
- `ConfigField.qml` `sliderC` (:191) + Manager glass slider (:515) → accent groove/handle.
- `WidgetConfigDialog.qml` "Reset to defaults" `Button` (:164) → `MButton`/token style.
- Dialog footers (`WidgetConfigDialog` :30/:106, `Manager` :734/:791) → custom `footer:`
  with token buttons; custom `header:` for `confirmDialog`/`resetConfirm`/`addPicker`
  (they use Fusion title chrome). Give `confirmDialog` Text (:793) a width cap (auto-wide).
- `ScrollBar` (WidgetConfigPanel :40, ConfigField areaC, Manager ScrollViews) → dark track/handle.

**1c. Config-dialog live-preview overflow (P1-5).** The 340px preview renders the
**expanded** widget (designed for 720px), so multi-button action rows overflow and clip
under `WidgetChrome.body { clip:true }` (Focus 4-button row, Media transport, Countdown
label+date+Save, Hydration, Tasks add-row). Fix: render the preview at Edge proportions and
`scale` it down (the `EdgeClone` approach), OR let expanded action rows `Flow`/wrap.
Recommend the scale approach for true WYSIWYG.

**1d. Desktop affordances (P1-6).** Add `hoverEnabled: true` + `cursorShape:
Qt.PointingHandCursor` + a hover color to the clickable Manager chips (theme/accent/page/
column/orientation/add-widget) — pattern already exists in the nav delegate.

**1e. Polish (P2):** replace hardcoded `#0D1117` text-on-accent literals with
`m.textOnAccent` (Manager/EdgeClone/BackgroundPicker/ConfigField); drop the nested
ScrollView around the Images `GridView`; make `addPicker` responsive like `WidgetConfigDialog`.

## Phase 2 — More theme options

Add **6 theme modes** + **6 accents** with exact tokens (from analysis):
- Themes: `nord`, `dracula`, `solarized_dark`, `solarized_light` (LIGHT), `catppuccin`, `gruvbox`.
- Accents: `cyan`, `indigo`, `mint`, `coral`, `amber`, `magenta`.

Registration checklist (per theme): `Theme.qml applyTheme()` case (12 tokens) · Manager
theme model (`Manager.qml:430-439`) · hub `SettingsPanel.qml:84-93` · **if LIGHT**, add the
key to the label-color ternary in both pickers (`Manager.qml:451`, `SettingsPanel.qml:107`).
Per accent: `Theme.qml accentPresets` · Manager `m.accentPresets` · `SettingsPanel.qml:202`
(ConfigField auto-reads presets). **Rust/config is opaque → no schema change.**
Test: update the hardcoded 8-accent count/names in `tests/ui/tst_theme.qml:20-21`; add
`test_applyTheme_<key>` cases + keep the unknown→dark fallback assertion.

## Phase 3 — Robustness

**3a. Harden `_normaliseDoc` into a real validator (HIGH, highest-leverage).** In
`DashboardStore.qml`: `if (!Array.isArray(doc.pages)) doc.pages = []`; each page → object
with `Array.isArray(p.tiles)` (reset `[]` else) and a string `name` (default); each tile →
object with non-empty string `id` (drop/re-id else). Closes the corrupt/partial-config and
malicious-IPC break class (`load`/`applyExternal` currently gate on truthiness only, so
`"pages":5` reaches `Repeater`/`addTile` → TypeError, blank dashboard).

**3b. Other guards:**
- `ConfigField.qml` `tasks` `cur()` → coerce `Array.isArray(v)?v:[]`; guard `a[index]`.
- `manager_backend.h` RX buffer cap (drop >1 MB without newline) + log `fromJson` parse errors.
- `importImage` size/free-space guard before synchronous copy.
- Surface save failures for display-target/autostart (mirror the honest `isAutostart()` re-read).
- `numberC` reject non-finite typed input; confirm all numeric schema fields set min/max.

## Testing strategy (every change gated)

- **QPalette/control restyle:** headless — assert the restyled Switch/Slider/Button expose
  the token colors (extend `tst_gen_shared_ConfigField`/`tst_manager_dialog`/`tst_controls`);
  **GUI** — XENEON_GRAB config dialogs (countdown/weather/focus) + Appearance tab, confirm
  controls match the dark theme (before/after screenshots).
- **Preview overflow:** headless assert the preview content width ≤ pane and no clip on the
  Focus/Media action rows; GUI grab confirms.
- **Themes:** `tst_theme.qml` per-mode token + light-label assertions; GUI grab the Appearance
  theme row (14 themes) and apply 2–3 new ones via XENEON_GRAB.
- **Robustness:** new `tst_store_validation.qml` feeding malformed docs (`pages:5`, string
  tiles, tasks non-array, huge/∞ numbers) → store self-heals, no throw; C++ RX-cap unit test.
- **Regression:** full `./scripts/run_all_tests.sh` green; Rust/C++/QML suites.

## Verification (end-to-end)

1. `./scripts/run_all_tests.sh` → SUCCESS (incl. new theme + validation gates).
2. GUI (real display, XENEON_GRAB): Manager Appearance (new themes/accents), config dialogs
   for countdown/weather/focus/tasks (styled controls, no clipped preview), Images/Display;
   hub on-device config + a couple new themes applied.
3. Rebuild package, confirm version bump; visual diff before/after.

## Out of scope / leave alone (verified good)

`MButton`/`MSwitch`, widget text overflow guards, empty states, destructive-action confirms,
S2 binding re-assertion, debounced writes, geocode UX, responsive `WidgetConfigDialog`,
`deleteImage` traversal guard, `EdgeClone` WYSIWYG. Device-frame dark colors are intentional.
