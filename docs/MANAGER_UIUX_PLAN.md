# Manager UI/UX + Theme + Robustness - Fix Plan

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

## Phase 1 - Graphical / UI-UX (the "graphical bugs")

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
column/orientation/add-widget) - pattern already exists in the nav delegate.

**1e. Polish (P2):** replace hardcoded `#0D1117` text-on-accent literals with
`m.textOnAccent` (Manager/EdgeClone/BackgroundPicker/ConfigField); drop the nested
ScrollView around the Images `GridView`; make `addPicker` responsive like `WidgetConfigDialog`.

## Phase 2 - More theme options

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

## Phase 3 - Robustness

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

- **QPalette/control restyle:** headless - assert the restyled Switch/Slider/Button expose
  the token colors (extend `tst_gen_shared_ConfigField`/`tst_manager_dialog`/`tst_controls`);
  **GUI** - XENEON_GRAB config dialogs (countdown/weather/focus) + Appearance tab, confirm
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

---

## W2 - Design/Layout/Appearance clarity: audit + restructure (2026-07-16)

**Owner complaint:** "Some features in the Manager are still not 100% clear,
especially about Design/Layout/Appearance, and which setting is changing which
behavior."

**Method:** walked the real Manager as a stranger (`-DXENEON_QA_HOOKS=ON`,
`XENEON_GRAB` stills of every tab + config dialogs, isolated
`XDG_CONFIG_HOME`/`XDG_RUNTIME_DIR` sandbox), wrote down every point where a
label did not answer *what does this change, and where*. Then restructured.
Evidence PNGs (before/after per finding) live in the session scratchpad, not
the repo.

### Findings → fixes

| # | Finding (with before-still) | Fix (with after-still) |
|---|---|---|
| F1 | Two unlabelled "theme" controls: Appearance → "Theme" (the Edge) vs sidebar "MANAGER THEME" (this window). Nothing says which repaints what. | Sidebar renamed **"Manager window style"** + caption "This window only - your Edge's theme is set in Appearance."; Appearance section renamed **"Edge theme"** with a `Whole Edge` scope tag and a caption pointing back at the sidebar. |
| F2 | Every Appearance control edits the Edge, but the only rendering of the Edge (EdgeClone) lived on the Layout tab - theme/accent/glass changes gave zero visible feedback in-window. | Appearance is now two panes: controls left, a **read-only EdgeClone live preview** right (page chips included). Theme/accent swatches **preview on hover** (`previewTheme`/`previewAccent`, transient - store written only on click; `endThemePreview` restores). Glassiness already previewed live; now the preview is beside it. |
| F3 | Help card told users to "Switch 1 / 2 columns above" - that control was removed a release ago. | Stale line deleted; hints rewritten to the four real gestures. |
| F4 | Help card + config dialog claimed "changes apply live/instantly to the Edge" while the sidebar said "Hub offline (saved)". | One shared `liveNote` ("Hub connected - … immediately." / "Hub offline - saved, appear when the hub starts.") shown in the Layout hint card, the Appearance preview, and the config dialog. |
| F5 | Per-page background: a giant duplicate of the Appearance picker sat mid-Layout-tab, pushing the actual layout tool half off-screen; the two pickers differed only by prose. | Moved into the Layout helper column beside the clone as **"This page's background"** with a `This page only` scope tag and a one-line precedence note ("Use global" returns to the shared one). Appearance's picker header gained the matching `All pages` tag. |
| F6 | No control declared its scope; accent circles had no names. | **ScopeTag pills** on every section: `Whole Edge` (Edge theme, Accent colour, Effects, Orientation), `All pages` (Background), `This page only` (page background), `This widget only` (config dialog header). Accent circles gained name tooltips; accent caption notes that a widget can override it (⚙ → Widget appearance). Effects switches each carry a one-line consequence note (incl. "Reduce motion … wins over the two switches above"). |
| F7 | "Remove page" deleted a page + its widgets instantly - the only destructive click without a confirm. | `confirmRemovePage()` arms the shared confirm dialog, naming the page and its widget count. |
| F8 | Images tab spread its few rows over the full window height when empty. | Trailing `fillHeight` filler keeps the column top-packed. |
| F9 | (Follow-up item) The Manager registered the `systemSettings` OS reduce-motion probe but its Theme never read it - OS reduce-motion stilled the hub yet not the Manager previews. | `Theme.systemReduceMotion` bound with the hub's typeof-guard pattern; EdgeClone backdrops now key off `theme.effectiveReduceMotion`. |

### Deliberately unchanged
- No settings were added or removed; every capability (theme/accent/background/
  effects/orientation/per-page override/per-widget config) is intact.
- The shared `BackgroundPicker`/`ConfigField`/`WidgetConfigPanel` (ui/qml) were
  not touched - W1/W3 own that tree right now. The per-widget "Widget
  appearance" schema section still can't show a scope tag inside the shared
  form; the dialog-level `This widget only` pill covers it from the outside.
- Switch labels ("Widget glow", "Animated background", "Reduce motion") kept -
  tests and the hub's on-device panel use the same wording.

### Tests
`tst_manager.qml`: hover previews transient + restore, committed accent
survives theme hover, remove-page confirm (reject/confirm/clamp), exactly one
editable + one read-only EdgeClone, liveNote follows `hubConnected`, config
dialog scope tag. `tst_edgeclone.qml`: `editable:false` hides drag/⚙/✕/resize
affordances. Coverage gate: 100% (previewTheme, previewAccent,
endThemePreview, confirmRemovePage all claimed + backed).
