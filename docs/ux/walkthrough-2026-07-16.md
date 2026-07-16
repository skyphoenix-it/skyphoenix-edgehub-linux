# End-user validation walkthrough — 2026-07-16 (W5, beta plan)

Persona-driven walkthrough on the real machine (real compositor, real Xeneon
Edge attached on DP-3), executed by the W5 "rubber duck" agent as a stranger
who had read only `README.md`-level material, `docs/BETA_PLAN.md` and
`AGENTS.md` before driving the product. Findings stand on what the user
experience showed; code annotations were added afterwards to help whoever
fixes them.

- **Code under test:** commit `462da15` (branch `worktree-agent-aa4730643d86d3fd6`,
  clean tree), built with `-DXENEON_QA_HOOKS=ON`, Release.
- **Isolation:** every launch used `XDG_CONFIG_HOME=/tmp/claude-1000/xe-w5/cfg`
  and `XDG_RUNTIME_DIR=/tmp/claude-1000/xe-w5/rt` (short path — the control
  socket must fit `sun_path`; the session scratchpad path is >107 bytes and the
  hub correctly refuses it). Live launches used `WAYLAND_DISPLAY=
  /run/user/1000/wayland-0` (absolute) and **always `--windowed`**, placed on
  DP-2 by a KWin script matching **window PID** so the owner's windows were
  never touched.
- **Interaction method:** the `tests/hardware/` uinput harness was NOT run —
  its README/`edge_hw_test.py` keep the real `XDG_RUNTIME_DIR` and require "no
  hub already running", i.e. it targets the real socket. Instead a minimal
  self-contained injector was used against MY windows only: a virtual relative
  mouse with closed-loop positioning via `workspace.cursorPos` (KWin
  scripting), plus a minimal virtual keyboard; every click was preceded by a
  user-idle check + activate-and-verify (`activeWindow.pid == my pid`), and
  every step was screenshotted (`spectacle` active-window, verified first) or
  captured via `XENEON_GRAB`. Offscreen grabs (`QT_QPA_PLATFORM=offscreen`)
  were used whenever the owner was actively using the machine.
- **Grabs:** `/tmp/claude-1000/-home-simon-IdeaProjects-XeneonEdge-Linux/cc3f5c02-a801-4f39-936e-d4d0ed258239/scratchpad/grabs/`
  (not committed; ~45 PNGs named `p<persona>-<step>-*.png`).

## Owner-hub liveness proof (required)

**Before session:**

```
BEFORE-session liveness @ 2026-07-16T16:22:43.319612 -> {"type":"pong"}
```

(`/run/user/1000/xeneon-edge-hub-ctl` owned by PID 1918268, started 15:47:05.)

**After session:**

```
AFTER-session check @ ~18:05 -> socket /run/user/1000/xeneon-edge-hub-ctl no longer exists
```

The owner's hub (PID 1918268) and manager (PID 1924459) were **shut down
cleanly by their owner during the session**, not by this walkthrough:

- Both the socket AND `xeneon-edge-hub.lock` / `xeneon-edge-manager.lock` are
  gone — that is the graceful-exit path (a kill -9 would have left them).
- Every hub this session started logged `ControlServer listening on
  "/tmp/claude-1000/xe-w5/rt/xeneon-edge-hub-ctl"` — never the real path — and
  no `shutdown` was ever sent to the real socket (the only real-socket traffic
  was the two `ping`s above).
- The journal shows the owner actively working in `xeneon-edge-manager` and
  `systemsettings` 17:20–17:27, mid dev-loop (`/usr/bin/xeneon-edge-hub` was
  reinstalled at 16:22; `qmltestrunner` was running against the main checkout
  at 17:29). Restarting their hub was deliberately NOT done — it would race
  their test run.

**Session interference disclosure (affects evidence quality):** the machine's
owner interacted with this walkthrough's windows twice (journal: focus on my
hub PIDs 2096846 at 16:34–16:38 and 2282802 at 17:22). The first wizard run
was completed *by the owner* (layout `calm-focus`, autostart left on), and the
second run's preset selection was disturbed (finished as `health`). Findings
below never rest on those two contaminated steps. Three other agents were
concurrently running their own hub/manager builds (visible in `pgrep`/journal).

## Findings (ranked)

Severity: **BLOCKER** task failed · **MAJOR** needed guessing/retries ·
**MINOR** friction · **POLISH** cosmetic.

| # | Sev | Persona / step | Expected | What happened | Grab | Likely cause (annotation) |
|---|-----|----------------|----------|---------------|------|---------------------------|
| 1 | BLOCKER | All / any wizard finish or autostart toggle (isolated env) | An isolated hub (`XDG_CONFIG_HOME` set) never touches my real login session | The hub wrote `~/.config/autostart/xeneon-edge-hub.desktop` in the REAL config dir, `Exec=` pointing at this agent's worktree build. Happened twice (16:37, 17:26). If the owner had logged in meanwhile, a temporary QA build would have autostarted. Cleaned up via the product's own `setAutostart(false)` IPC (which honestly removes the entry — verified 0 files left) | `p1-30-wiz2-p4-options.png`; file mtimes + `live_hub.log` "Autostart entry written" | `app/src/autostart.cpp:20` hardcodes `QDir::homePath() + "/.config/autostart"` instead of `QStandardPaths::writableLocation(ConfigLocation)`; ignores `XDG_CONFIG_HOME`. Bites every E2E/CI run on a dev box, violates XDG spec |
| 2 | BLOCKER | Developer / "connect my CI status to a URL" on-device, landscape | Expanded widget view shows the URL form | In 2560×720 the expanded view shows ONLY preview + "Reset to defaults" + "Done"; the hint says "Add a URL in settings" but no settings exist anywhere on screen (a ~10px sliver at the right edge is the collapsed form). Same for every widget (clock shows nothing but Reset/Done). Portrait shows the full form. On a landscape-mounted panel, on-device configuration is impossible | `p2-02-httpjson-expanded.png` (landscape, no form) vs `p2-04-httpjson-expanded-portrait.png` (full form); live confirm `p1-21-clock-expanded-live2.png` | `ui/qml/Dashboard.qml:1040-1108` — in `ovlWide` the preview column takes `overlay.width * 0.46` + `fillWidth`, and `WidgetConfigPanel` (line 1095) collapses to ~zero width. Also hides the per-widget "Card backdrop" control (finding 6) in landscape |
| 3 | MAJOR | First-run / "pick a preset" after setup | Some button reopens the 15-preset library | No path exists. `PresetCatalog.list()` is consumed ONLY by `FirstRunWizard.qml:244`; the only post-setup route is the `--reset-wizard` CLI flag, which a stranger cannot know | `p1-27-wiz2-p3-presets.png` (the library exists and is excellent — once) | `ui/qml/PresetCatalog.qml` has no consumer in `Dashboard.qml`, settings overlay, or Manager. The library is wizard-only by construction |
| 4 | MAJOR | All / any toolbar (software rendering) | Icons visible | Under a software scenegraph every `AppIcon` renders as an EMPTY square — dashboard corner buttons, steppers, config icons, all of them. Reproduced with `QT_QUICK_BACKEND=software` and on the offscreen platform; GPU rendering is fine (live grabs show icons). Affects VMs/remote sessions/no-GL users and every headless QA/marketing capture | `zoom-x-icons-software-backend.png` (blank) vs `p1-16-live-dashboard.png` (fine) | `ui/qml/widgets/AppIcon.qml:18-36`: glyph is tinted via `MultiEffect` and the raw `Image` is hidden (`visible: !tint`); when the effect can't render there is no fallback. Fallback = show the untinted image when effects are unavailable |
| 5 | MAJOR | First-run / wizard "Almost Done!" | Finishing quickly leaves my system unchanged | "Start automatically when I log in" is pre-CHECKED (plus finding 1 = writes outside the sandbox). A quick Finish silently modifies login behaviour. The three checkboxes are also visibly tiny for a touch panel (my scripted tap and a fat finger miss alike) | `p1-30-wiz2-p4-options.png` | `ui/qml/FirstRunWizard.qml:336-338` (`autostartCheck, checked: true`); default-on is a product decision worth revisiting for beta; checkbox indicator size vs `theme.touchPrimary` |
| 6 | MAJOR | Developer + Neurodivergent / "check what the app talks to"; "per-widget backdrop off" | A runtime view of network activity; a reachable per-widget setting | README promises "per-host counters for what was actually sent" and `NetHub.qml:44` says the counters are "for Diagnostics" — but Diagnostics has no Network tab and no UI anywhere surfaces counters, the kill switch state, or the allowlist. Meanwhile the Weather widget fetched real Berlin data with zero interaction (default preset + default location). The per-widget "Card backdrop" option exists in the schema but is unreachable in landscape (finding 2) | `p2-05-diagnostics-portrait.png` (tabs: Overview/Config/Screens/Log only); `p1-13-clock-page.png` (Berlin 30°C, never configured) | `ui/qml/Diagnostics.qml` (no NetHub surface); `ui/qml/widgets/NetHub.qml:44` (counters exist, unread); `ui/qml/WidgetConfigSchema.qml:31` (cardBackdrop in the hidden panel) |
| 7 | MINOR | All / Diagnostics view | Matches the product's theme, readable | Light/white page inside a dark product; the section heading under the tabs is pale blue on near-white (barely legible); "Build: unknown" in the version box | `p2-05-diagnostics-portrait.png` | `ui/qml/Diagnostics.qml` — root lacks a themed background; heading uses accent-on-light; build metadata never populated |
| 8 | MINOR | First-run / wizard display step | The detected Edge is pre-selected | The Edge is highlighted green + "Detected" but NOT selected; "Next" stays disabled until you also press "Select" on the highlighted row — reads as already-chosen | `p1-06-wizard-p2.png`, `p1-25-wiz2-p3-presets.png` (Next still disabled) | `FirstRunWizard.qml` display step: detection sets highlight, not `selectedScreen` |
| 9 | MINOR | First-run / dashboard first look | All my widgets fit, or the UI shows there is more | Third tile (CPU) is hard-clipped by the screen edge with no scroll indicator; it looks broken until you discover the page row scrolls horizontally. Swiping to change pages scrolls the row instead — two gestures share one axis with no affordance | `p1-16-live-dashboard.png` (clipped), `p1-23-page2-after-swipe.png` (row scrolled, same page) | `ui/qml/Dashboard.qml:600-614` — intentional long-axis `Flickable` inside the `SwipeView`; missing scroll indicator/fade-edge |
| 10 | MINOR | Manager-only / rename a page | Typed name is saved when I move on | Rename commits only on Enter (`editingFinished`); clicking a wallpaper/another control does NOT blur the `TextField` (buttons take no focus), so the field shows "Yen" while pill + store still say "Home" — silent divergence until Enter | `p3-21-mgr-renamed-page.png` (field Yen, pill Home) | `manager/qml/Manager.qml:431` — `store.renamePage` wired to editingFinished only; commit on focus-loss/inline as-you-type would match the instant-apply of every neighbouring control |
| 11 | MINOR | Manager-only / Layout tab, first open | See the device preview + how to edit | At the default window size the live preview, "Add widget" and the "This is your Edge" help card sit half below the fold, and the pane does not wheel-scroll — you must resize the window to find the core editing surface | `p3-20-mgr-live-layout.png` (clipped) vs `p3-32-mgr-wheel-preview.png` (tall window, complete) | `manager/qml/Manager.qml` Layout pane: no ScrollView at small heights; default/min window size vs content height |
| 12 | MINOR | Manager-only / Appearance toggles | All toggles visible | The "Reduce motion" toggle row clips off the right edge at default width | `p3-28-mgr-appearance-bottom2.png` (label cut to "Reduce m…") | Manager Appearance toggle `Row` lacks wrapping/`fillWidth` at narrow widths |
| 13 | MINOR | Manager-only / Display tab with hub offline or no screens | Explanation of why no screens are listed | Header says "Choose which screen the hub runs on" but nothing renders below it (offline single-screen case). With 3 real screens it is complete and clear (Target ✓) | `p3-13-mgr-tab3.png` (empty) vs `p3-35-mgr-display-3screens.png` (good) | Display list needs an empty-state row ("No displays detected…") like the wizard has |
| 14 | MINOR | First-run / "make the clock bigger" | Know what the resize control will do | Edit-mode resize is one tap (great) but the control gives no hint of direction/next size (cycles), and the repack instantly relocates other tiles out of view — the CPU widget "vanished" (it had moved along the scrollable row) | `p1-17-edit-mode.png`, `p1-18-clock-resize-tap.png` | Edit-mode resize button cycles `WidgetSizes` entries; no size badge/preview on the button |
| 15 | MINOR | Config readers (developer) / reduce-motion & theme | One source of truth | Two representations disagree after UI changes: `ui_state` `appearance.reduceMotion=true` / `themeMode="nord"` vs `[theme] reduced_motion=false` / `mode="dark"` in the same config.toml | isolated `config.toml` after `p4-07` + `p3-24` | `core/src/config.rs` `[theme]` keys are legacy vs `DashboardStore` appearance; stale keys mislead anyone editing config.toml by hand |
| 16 | POLISH | First-run / expand a widget | Tapping the tile opens it | Only the small ↗ corner icon expands; tile-body tap does nothing (Manager help card even says "Tap a tile … to configure" — true in Manager, not on-device) | `p1-20-clock-expanded-live.png` (body tap: nothing) | `Dashboard.qml` tile MouseArea vs expand affordance |
| 17 | POLISH | First-run / wizard preset page, landscape | Next/Back visible | Nav is below the fold; page scrolls fine (flick/wheel) but nothing says so | `p1-27-wiz2-p3-presets.png` vs `p1-29-wiz2-p3-bottom.png` | Wizard page Flickable without indicator |
| 18 | POLISH | First-run / clock config | Options, or no config affordance at all | Clock's expanded view offers only "Reset to defaults" + "Done" (in landscape; portrait has General/Appearance sections) — Reset with nothing visible to reset reads oddly | `p1-14-clock-expanded.png` | Consequence of finding 2; clock also genuinely has few settings |
| 19 | POLISH | QA/capture tooling | Manager grabs honour size hooks | `XENEON_GRAB_W/H` is hub-only; Manager grabs are stuck at the offscreen screen's clamp (760×760) unless given an offscreen config file | `p3-00…05` vs `p3-10…14` | `manager/src/main.cpp:135-152` lacks the resize branch `app/src/main.cpp:690-698` has |
| 20 | POLISH | Beta legal item (confirmation) | — | Distro/brand names ship today in both apps: themes Arch, CachyOS, Debian, Fedora, Pop!_OS, Nord, Dracula, Solarized, Gruvbox, Catppuccin, Tokyo Night; backgrounds "Fedora Loops", "Arch Peaks", "Aubergine Ribbons" | `p4-02-settings-scrolled1.png`, `p3-11-mgr-tab1.png` | Matches the open "lawyer pass" decision in `docs/BETA_PLAN.md` |
| 21 | POLISH | Grab pipeline only | Themed buttons offscreen | Wizard "Get Started" renders as a light default-styled button in offscreen grabs; correct dark button live | `p1-01-first-launch.png` vs `p1-05-wizard-p1-live.png` | Palette propagation on the offscreen platform; capture-only |

## What worked well (do not break)

- **Display detection**: the real Edge (Cyrix, 720×2560, DP-3) is auto-detected
  and badged in the wizard; selected state is unmistakable (✓ + outline);
  the no-displays case has explicit copy. `p1-06`/`p1-07`.
- **Interrupted first-run recovers**: killing the app mid-wizard brings the
  wizard back (`first_run_complete=false` until Finish). `p1-02`.
- **The preset library** is genuinely good: 15 presets + blank, each with a
  blurb that sells the outcome ("Your build and your box — CI status and a
  number you watch…"); the Developer preset lands with pre-titled "CI status"
  and "Open PRs" widgets and honest empty states. `p1-27`, `p2-10`.
- **Secrets are discoverable, not documentation-only**: the Bearer-token field
  in BOTH hub and Manager carries the full `${env:MY_TOKEN}` / `file:` guidance
  inline, including "resolved only when the request is made and never written
  to disk". Persona 2 met the no-plaintext goal without opening a single doc.
  `p2-04`, `p2-07`.
- **Egress posture**: one audited gate (`NetHub.request()`), Rust core with no
  network stack, update check off-by-default with candid copy in the on-device
  settings ("EdgeHub never phones home on its own…"). The architecture matches
  the README claims (the missing piece is a UI surface — finding 6).
- **Scope clarity is already half-solved (W2)**: per-page background copy
  ("Overrides the global default (set in Appearance) for the current page
  only"), Appearance's "Background (global default)… A page can override",
  settings panel footer "Changes apply instantly. Your Xeneon Edge display
  will use these settings across all widgets", Display's "Applies next time
  the hub starts". Every one of these let the persona predict scope before
  acting. `p3-20`, `p3-28`, `p4-06`, `p3-35`.
- **Cross-app round-trip**: reduce-motion toggled on-device shows up in the
  Manager's toggles; Manager wallpaper/theme persist correctly scoped; the
  Manager's live preview clone mirrors the device. `p3-28`, `p3-30`.
- **Edit mode**: two taps from dashboard to a bigger clock; per-tile
  delete/move/resize affordances are clear; "This is your Edge" help card in
  the Manager is exactly the right teaching copy. `p1-17`, `p1-18`, `p3-32`.
- **A11y groundwork**: Okabe–Ito colour-blind-safe accent row, Contrast and
  Light themes, reduce-motion copy that explains the difference from
  "Animated background". `p4-05`, `p4-06`.
- **IPC honesty**: `setUiState` acks reflect the real apply result;
  `setAutostart(false)` removes the real entry and the Manager reads back the
  entry (not the flag). Control socket lives in the per-user runtime dir with
  an absolute path and refuses unsafe fallbacks (`control_socket_path.h`).
- **Single-instance guards** on both apps, with QA bypass only in QA builds.

## Persona task completion

| Persona | Task | Result |
|---------|------|--------|
| First-run | Fresh config → wizard | **done** (all 4 pages driven; interruption recovery verified) |
| First-run | Pick a preset (in wizard) | **done** (library reachable, default "Productivity" pre-selected silently) |
| First-run | Pick a preset (after setup) | **failed** — no UI path exists (finding 3) |
| First-run | "Make the screen calmer" | **done** — reduce motion + animated-bg off + calm-ish themes; 1 tap + 4 panel-scrolls to reach (finding: control cluster at the very bottom) |
| First-run | "Make the clock bigger" | **done** — edit mode, 2 taps (finding 14 on predictability) |
| Developer | Apply developer preset | **done** (via wizard; also seeded via `starter_layout`) |
| Developer | Connect CI status to a URL | **done-with-struggle** — full form in portrait/Manager; **failed on-device in landscape** (finding 2) |
| Developer | Token without plaintext | **done** — `${env:}` inline in the token field itself |
| Developer | Check what the app talks to | **done-with-struggle** — README/architecture yes, runtime surface no (finding 6) |
| Manager-only | Change theme | **done** (Nord; persisted; scope implied global, not stated) |
| Manager-only | Wallpaper on ONE page | **done** — scope explicit in copy and verified page-local in persisted state |
| Manager-only | Resize a widget | **done-with-struggle** — corner-drag affordance + help card present; drag interrupted by owner activity, resize executed on-device instead; config verified `1x1.5` |
| Manager-only | Rename a page | **done-with-struggle** — Enter-commit quirk (finding 10) |
| Neurodivergent | Find reduce-motion | **done** — 5 interactions deep, zero dead ends, excellent copy once found |
| Neurodivergent | Calm themes | **done-with-struggle** — no theme named "Calm" (beta default question still open); OLED/Graphite/Dark nearest |
| Neurodivergent | Per-widget backdrop off | **failed on-device (landscape)** / possible in portrait & Manager config dialog (findings 2, 6) |

## Honest limits

- Stills cannot show motion. Live sessions ran on the real compositor and the
  reduce-motion state change was verified in persisted state + static backdrop
  in subsequent grabs, but easing/smoothness quality (W3) was NOT assessed —
  no finding here either way, marked observational.
- The machine's owner was actively using the computer throughout; two wizard
  steps were contaminated by their input (disclosed above), the Manager
  corner-drag resize burst was aborted for the same reason. All injections
  were gated on pointer-idle checks + focus verification; one early click
  (before the protocol was hardened) most likely landed in the owner's browser
  — harmless but noted.
- The `tests/hardware` uinput harness was not exercised (targets the real
  socket by design). Synthetic input came from a session-local injector
  instead; touch-specific behaviours (long-press, flick velocity, multi-touch)
  were not tested.
- Offscreen grabs render without GPU effects: icon blanks there are finding 4's
  software-pipeline case, not the live experience (live grabs confirm icons).
- The wizard was never completed with autostart unchecked (owner interference
  first, a missed 14px checkbox second — itself evidence for finding 5), so
  the `applyAutostart(false)`-on-Finish path is untested; the IPC path was
  tested and works.

## Follow-ups suggested (not done here)

1. Fix `autostart.cpp` to honour `XDG_CONFIG_HOME` (finding 1) and add a
   runtime-E2E assertion that an isolated hub leaves `~/.config` untouched.
2. Fix the landscape expanded-config layout (finding 2) — this single fix also
   restores per-widget backdrop, KPI/HTTP configuration, and "Card backdrop"
   discoverability on landscape mounts.
3. Add a "Screens / Presets" entry point post-wizard (finding 3) — the library
   is the product's best asset and is currently shown exactly once.
4. Give `AppIcon` a no-effects fallback (finding 4).
5. Surface the NetHub attestation counters in Diagnostics (finding 6) — the
   data already exists; this closes the README promise.
