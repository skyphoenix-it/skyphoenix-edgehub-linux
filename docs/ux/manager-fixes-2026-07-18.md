# Manager fixes & full-control pass - 2026-07-18

Follow-up to [`manager-audit-2026-07-16.md`](manager-audit-2026-07-16.md). The
owner installed the build and hit a set of real problems; this records what was
fixed. Guiding principle (owner's words): **the Manager is the full control
surface; the Hub is the simpler display, focused on showing things.**

All changes are on `v1.0-alpha`. Full suite green (Rust, QML GUI, C++ ctest,
QML behaviour matrix 98.8%, all 8 runtime E2E); theme 98/98, manager 40/40.

## Fixed

- **Scroll lag (Manager).** The live `EdgeClone` preview repainted every frame
  while another tab was shown: the animated "orbs" backdrop defaulted ON and the
  tick/metrics timers ran unconditionally (a second preview on the Appearance tab
  made it worse). Backdrop + timers now gate on the clone's visibility
  (`previewLive`), and the preview's `animatedBg` defaults to the hub's calm
  value. Swatch hover-preview is also debounced so wheel-scrolling the grid can't
  storm `applyTheme`.
- **Glassiness slider did nothing.** It was wired, but on the default dark theme
  card and page are near-identical near-blacks, so varying only the fill alpha was
  invisible without a wallpaper. Lightening the fill to fix that would push
  mid-tone accents (Fedora's navy) below the 3:1 WCAG bar. Glass now drives a
  **card border rim-light + top sheen** (channels no contrast gate constrains);
  the fill keeps its alpha behaviour but is now a notifiable property.
- **"Where is autoupdate?"** The update-check flag was only reachable in the
  hub's buried on-panel settings. A discoverable **"Check for updates
  automatically"** toggle is now in the Manager (Display tab). The Manager only
  sets the flag; the hub still runs the actual check through its audited gate, so
  no new egress surface.

## Appearance restructure (audit F3/F5)

- The **Manager-window style** control moved out of the sidebar and into the
  Appearance tab, beside the Edge theme - the audit's "two unlabelled theme
  controls in two places" confusion. Both now carry scope pills.
- The 29-swatch Edge-theme grid is **collapsed to a curated 8** with "Show all
  themes" (the selected theme always shows), so the tab isn't swatch-dominated.

## New full-control parity

- **Start-from-a-preset "screens" picker** (the curated `PresetCatalog`, applied
  via `store.resetTo` → persisted + pushed live; preserves the user's
  reduce-motion choice).
- **Diagnostics** card (About): connection, displays, and the raw config on
  demand - points to the hub for live egress counters rather than faking zeros.
- **Reset to default layout** (keeps uploaded images).
- Per-page background overrides were already present (Layout tab).

## Branding

- The lockup is now **"EdgeHub"** in a bundled brand wordmark face
  (**Chakra Petch**, SIL OFL 1.1 - a close free stand-in for the SKYPhoenix IT
  logo lettering; swap the files to use the real font later), over a small
  **"by SKYPhoenix IT"** and a small logo beneath (sidebar + About).

## Marketing

- The 11 curated marketing stills were **regenerated from the fixed build**
  (corrected widget alignment, visible glass cue, new Manager branding + layout).

## Note for the next reader

`qmltestrunner` runs test functions **alphabetically**, so a test that mutates the
shared store must restore it (emit `backend.configChanged()`) or a later test
inherits the state.

> **CORRECTION (2026-07-19).** This note previously read: *"`tst_manager` is heavy
> (~250–300 s) - expected, not a hang."* **That was wrong, and the wrongness was
> load-bearing.** `tst_manager.qml` carried an unmemoised multi-axis scene-graph
> walk: it grew from 7 MB to **20 GB RSS in 25 seconds** and never completed. The
> "expected slowness" framing is why nobody investigated. After the fix it runs in
> **1.1 s at 105 MB peak**, 54/54 passing. Two sibling copies of the same bug
> existed (`tests/gui/GuiUtil.js`, `tests/ui/tst_gen_notes.qml`); one of them
> triggered a system-wide kernel OOM that killed the developer's IDE. If a test in
> this repo is "just slow", treat that as a defect report, not a fact of life.
> Guard: `scripts/check_tree_walks.py`, wired into `scripts/run_all_tests.sh`.
