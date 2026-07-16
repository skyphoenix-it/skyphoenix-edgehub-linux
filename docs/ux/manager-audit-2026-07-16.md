# Manager UX audit — 2026-07-16 (W2, beta plan)

The owner's complaint, verbatim: _"Some features in the Manager are still not
100% clear, especially about Design/Layout/Appearance, and which setting is
changing which behavior."_

This is a **control-by-control audit**, walked as a new user, of every panel of
`xeneon-edge-manager`. For each control it answers the four W2 questions:

1. **What does it change?**
2. **At what scope?** (this widget / this page / whole Edge / this computer / this window)
3. **Is the label plain language?**
4. **Do you see the effect before committing?**

## Method & evidence

- **Code under test:** worktree `agent-ad247f38e94a6ed34`, HEAD `c933264`, clean
  tree. Built Release with `-DXENEON_QA_HOOKS=ON`.
- **Isolation:** every launch used `XDG_CONFIG_HOME`/`XDG_RUNTIME_DIR` under the
  session scratchpad and a fake `HOME` via `env -i`. `~/.config/xeneon-edge-hub/`
  was never read or written; no hub was started; no test binary was run directly.
- **Grabs:** all five tabs at 1440×1300 (the shipped default window size) and the
  Layout/Appearance tabs at 1120×760 (`minimumWidth`×`minimumHeight`), offscreen,
  in the scratchpad `grabs/tab{0..4}.png` + `grabs/small{0,1}.png` (not committed).
- **Prior art:** a first W2 pass already landed in `e5bf83f` (scope pills on the
  Design/Layout/Appearance sections, the Appearance live-preview pane, hover
  try-on, the "Manager window style" relabel). This audit is therefore the audit
  that pass never wrote down, **plus** what a walk of the shipped result still
  shows. Several items below are recorded as *already fixed* precisely so the
  next reader does not re-fix them.
- The W5 walkthrough (`docs/ux/walkthrough-2026-07-16.md`) tested `462da15`,
  which **predates** `e5bf83f`. Its Manager findings (10–13) are re-checked here
  against the current build rather than inherited.

## Control inventory

Scope column = the scope the control **actually** has (verified in
`DashboardStore.qml` / `ManagerBackend`), not what the UI claims.

### Sidebar (always visible)

| Control | Changes | Real scope | Label plain? | Preview before commit? | Verdict |
|---|---|---|---|---|---|
| Layout / Appearance / Images / Display / About | navigation | — | yes | n/a | OK |
| Manager window style: Dark / Light / Default | this app window's chrome (QSettings) | this window | yes, since `e5bf83f` | instant, self-evident | **F5** — scope stated in prose only, no pill like every other control |
| Hub dot + "Hub connected (live)" / "Hub offline (saved)" | nothing (status) | — | yes | n/a | OK — the best copy in the app |
| Start hub / Stop hub | runs/stops the hub process | this computer | yes | n/a | OK |

### 1. Layout

| Control | Changes | Real scope | Label plain? | Preview before commit? | Verdict |
|---|---|---|---|---|---|
| Page chips (Focus / Day / System) | which page you are editing | — | yes | n/a | OK |
| "+" chip | adds a page | whole Edge (a new page) | icon-only | instant | **F9** — renders as a blank chip offscreen/software (AppIcon, not Manager) |
| "Page name:" field | renames the current page | this page | yes | commit on Enter only | **F1** — commits on Enter only; switching page **destroys** the typed name |
| "Remove page" | deletes page + its widgets | this page | yes | confirm dialog | OK (`e5bf83f`) |
| EdgeClone tile drag / corner resize / ⚙ / ✕ | layout of this page | this page | help card explains | live, WYSIWYG | OK — the strongest surface in the app |
| "Add widget" | adds a widget | this page | yes | picker, then instant | **F4** — the picker never says *which page* it adds to |
| "This page's background" + picker | page background override | this page | yes + pill + precedence copy | applies on click | OK (`e5bf83f`) |
| Help card "This is your Edge" | nothing | — | yes | n/a | OK |

### 2. Appearance

| Control | Changes | Real scope | Label plain? | Preview before commit? | Verdict |
|---|---|---|---|---|---|
| Tab subtitle "Hover a swatch to try it in the preview — nothing is applied until you click." | nothing | — | yes | — | **F2** — **false for the Background chips on the same tab**: they commit on click with no hover try-on |
| "Edge theme" (29 swatches), pill `Whole Edge` | `appearance.themeMode` | whole Edge | yes | hover try-on | OK (`e5bf83f`) |
| "Accent colour" (14 circles), pill `Whole Edge` | `appearance.accent` | whole Edge | name on hover tooltip | hover try-on | OK (`e5bf83f`) |
| "Background", pill `All pages` | `appearance.bgStyle` / `appearance.wallpaper` | every page, unless a page overrides | yes | **no** — click commits | **F3** (vocabulary), **F2** (copy) |
| Glassiness slider | `appearance.glass` | whole Edge | yes + % + one-liner | live while dragging | OK |
| Widget glow / Animated background / Reduce motion | `appearance.*` | whole Edge | yes + consequence line each | applies on toggle, preview adjacent | OK (`e5bf83f`) |

### 3. Images

| Control | Changes | Real scope | Label plain? | Preview before commit? | Verdict |
|---|---|---|---|---|---|
| "Import image…" | copies a file into the images dir | this computer | yes | n/a | OK |
| **Click an image card** | sets `appearance.wallpaper` | **whole Edge** | "Click an image to use it as the wallpaper." | no | **F6** — the only control in the app that changes the whole Edge with **no scope tag and no live preview on the tab**. Nothing says every page changes. |
| Trash icon on a card | deletes the file, clears it from global + per-page backgrounds | whole Edge | icon-only | confirm dialog | OK |

### 4. Display & Startup

| Control | Changes | Real scope | Label plain? | Preview before commit? | Verdict |
|---|---|---|---|---|---|
| Tab subtitle "Choose which screen the hub runs on. **Applies next time the hub starts.**" | nothing | — | yes | — | **F7** — sits above Orientation + autostart, which do **not** wait for a restart. Read as tab-level guidance it is simply wrong. |
| Screen cards + "Set as target" | which screen the hub opens on | this computer, next start | yes | no (inherent) | **F8** — no scope pill; and with **zero screens the list renders nothing at all** (reproduced, `grabs/tab3.png`) |
| "Orientation", pill `Whole Edge` | `appearance.orientation` | whole Edge, live | yes + Auto caveat | no | OK (pill correct) |
| "Start the hub automatically on login" | writes `~/.config/autostart/*.desktop` | this computer | yes | n/a | **F8** — no pill, no note; the only control that touches the login session |

### 5. About

| Control | Changes | Real scope | Verdict |
|---|---|---|---|
| Website | opens skyphoenix-it.com | — | OK |
| **GitHub** | `Qt.openUrlExternally("#")` | — | **F10** — placeholder URL: the button does nothing |

### Per-widget config dialog (⚙)

| Control | Changes | Real scope | Verdict |
|---|---|---|---|
| Header pill `This widget only` | — | this widget | OK (`e5bf83f`) — the model the rest of the app should copy |
| Schema form fields | that tile's settings | this widget | OK — live preview beside the form |
| "Reset to defaults" | that tile's settings | this widget | OK — confirms |

## Findings (ranked)

**F1 — A typed page name is silently destroyed.** `Page name:` commits only on
`editingFinished`. Nothing else in the Layout pane takes keyboard focus (chips
and buttons are `MouseArea`s), so the field never blurs. Type `Yen`, click
another page chip, and `onCurrentPageIndexChanged` overwrites the field with the
*new* page's name — the rename is gone, with no error and no trace. W5 finding
10 saw the divergence; the data loss is worse than reported. Every neighbouring
control applies instantly, so the field's Enter-only contract is unguessable.

**F2 — The Appearance tab makes a promise it breaks two sections later.**
"Hover a swatch to try it in the preview — nothing is applied until you click"
is true of themes and accents, and false of the Background chips directly below,
which commit on click. A user who trusts the header will change their background
by hovering-then-clicking to "try" it. The copy must describe what is true.

**F3 — Two words for one scope, with nothing to distinguish them.** Theme and
accent are pilled `Whole Edge`; Background is pilled `All pages`. Both are
Edge-global. The distinction is real (a page can override the background, but
not the theme) but is nowhere stated, so the pills read as two arbitrary
synonyms — which is precisely the owner's "which setting changes which
behavior". The pills are a vocabulary; a vocabulary needs definitions.

**F4 — "Add widget" never says where the widget lands.** With three pages, the
picker's only clue is that you were on a page when you opened it.

**F5 — The Manager's own chrome switch is the only Design control with no pill.**
It has a caption instead. Uniformity is the point of a scope tag: an exception
teaches the user the pills are decorative.

**F6 — Clicking a thumbnail on the Images tab silently re-skins every page.**
The card click writes `appearance.wallpaper`. The tab has no scope pill, no
preview, and the copy ("use it as the wallpaper") does not say *whole Edge*. It
is the largest unlabelled scope jump in the app.

**F7 — The Display tab's restart caveat is attached at the wrong altitude.**
It belongs to the screen picker; as a tab subtitle it wrongly disclaims
Orientation (live) and autostart (immediate).

**F8 — Display's screen picker and autostart carry no scope, and the screen list
has no empty state.** With no screens detected the tab shows a sentence about
choosing a screen followed by blank space, then Orientation — so Orientation
looks like the answer to "choose which screen". (Reproduced offscreen; W5
finding 13 saw the same on a real box with the hub offline.)

**F9 — `AppIcon` renders blank without GPU effects**, so the Layout tab's
add-page "+" chip is an empty box in offscreen/software rendering
(`grabs/tab0.png`). This is W5 finding 4 (`ui/qml/widgets/AppIcon.qml`), outside
this workstream's ownership; recorded here because it hits the Manager too.

**F10 — About → GitHub opens `"#"`.** A button that does nothing.

**F11 — Wallpaper names collide with theme names.** `Midnight`, `Nebula`,
`Aurora`, `Ocean`, `Ember`, `Sunset` are each *both* an Edge theme (Appearance)
*and* a wallpaper (background picker). "Set Midnight" is ambiguous in the one app
where scope clarity is the goal. `ui/qml/WallpaperCatalog.qml` is outside this
workstream's ownership — recorded for the owner.

**F12 — Reduce motion is 29 decorative swatches deep.** At the minimum window
size the theme grid is two columns wide, so the Effects group (glow, animated
background, reduce motion) sits ~15 rows below the fold (`grabs/small1.png`).
The single most consequential accessibility control in the app is the hardest to
reach. W5's neurodivergent persona found it, but needed five interactions.
Grouping by intent would put "calm" near the top; that is a bigger change than a
clarity pass and is **not** attempted here.

## Re-checked W5 Manager findings

| W5 # | Status on `c933264` |
|---|---|
| 10 — rename commits on Enter only | **still present**, and worse (F1). Fixed in this pass. |
| 11 — Layout tab clipped, no scroll at small heights | **already fixed** by `e5bf83f` (the background picker moved into the helper column's `ScrollView`). Verified at 1120×760: clone, "Add widget" and the help card are all visible (`grabs/small0.png`). |
| 12 — "Reduce motion" label clipped at narrow width | **already fixed** by `e5bf83f` (the switch rows are `ColumnLayout` + `fillWidth`). |
| 13 — Display tab has no empty state | **still present** (F8). Fixed in this pass. |

## What this pass changes

F1, F2, F3, F4, F5, F6, F7, F8 — all inside `manager/`. Deliberately **not**
attempted: F9, F11 (other agents own those files), F10 (needs a real URL from
the owner), F12 (restructure, not clarity).

## Unrelated defect found while testing (not this workstream's file)

`tests/ui/tst_meds.qml` is **midnight-sensitive** and fails between 00:00 and
05:00 local time. `hhmm(-300)` formats "now − 5h" as a bare `HH:mm` with no
date, so at 00:10 it yields `19:10`, which `MedsWidget` reads as 19:10 **today**
— i.e. ~19 hours in the future. `test_a_passed_dose_is_never_red_and_never_missed`
then sees an *upcoming* dose instead of a passed one and fails; a nearby
`MedsTileInput` case flakes the same way.

Proof it is neither this branch's doing nor a real regression: the failure
reproduces on a pristine tree with this branch's changes stashed, and the whole
suite passes on the unmodified code under `TZ=Asia/Tokyo` (wall clock 07:13, no
wrap). `f5dc699` already de-flaked one midnight-sensitive test; this is another
instance of the same class. Owner of `tests/ui/tst_meds.qml` should give the
helper a real date or freeze the clock.

## The scope vocabulary (now fixed and defined)

Every scope pill in the Manager draws from exactly this list, and each pill now
carries a hover `detail` that states the rule precisely:

| Pill | Means |
|---|---|
| `This widget only` | one tile; other tiles of the same type are untouched |
| `This page only` | one page; other pages are untouched |
| `All pages` | the default for every page — **a page can override it** (Layout → "This page's background") |
| `Whole Edge` | every page and every widget; no per-page override exists |
| `This computer` | this machine's hub/session — not stored in the Edge layout |
| `This window only` | the Manager's own chrome; the Edge is untouched |
