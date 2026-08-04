# Session handover — 2026-08-04

Written at Simon's request, at the point where **all 30 catalog widgets have had
their first audit pass**. This is the "pick it up cold" document: what is done,
what is not, what needs deciding, and which traps cost time so they are not paid
for twice.

Companion documents, all still current:

| Document | What it owns |
|---|---|
| `BACKLOG.md` | The item list. Sections are load-bearing — see "How the backlog is organised" below. |
| `docs/testing/widget-audit-2026-08-03.md` | The 1487-line running record of the widget pass. Per-widget findings live there, not here. |
| `AGENTS.md` | Build, test, layout, FFI rules. Read before touching anything. |
| `docs/agent-memory/SESSION-HANDOFF-2026-07-20.md` | The previous handover. Superseded for status, still useful for the test-regression history. |

---

## 1. Where things stand in one paragraph

`master` is green and carries a working v1.0-alpha product: 30 widgets, a
Dashboard with pages and an idle-gated auto-cycle, a companion Manager app that
live-pushes over a control socket, a Rust core behind a hand-written C FFI, and a
CI pipeline of ~30 checks including a nested-compositor GUI suite and reviewed
visual baselines. The widget feature audit is **complete for all 30 widgets**.
What blocks v1.0 is now mostly **decisions**, not code — and one real class of
engineering debt (test integrity) that has been productive enough to be worth
continuing.

---

## 2. What shipped in this session (2026-08-04)

Four PRs, all merged to `master` except the last (open at time of writing).

| PR | What | Why it mattered |
|---|---|---|
| #21 | `check_ui_links.sh` and `check_tree_walks.py` reported OK when they had done no work | Seventh and eighth instances of the repo's most persistent defect class |
| #22 | New gate `scripts/check_bundled_fonts.py` | The bundled-font contract spanned three files nothing compared |
| #23 | Pinned the D1/D2 defaults; removed an assertion that could not fail | Both decisions were already shipped; the guards protecting them were weak |
| #24 | Killed a live CI flake; pinned the invariant a visual baseline rests on | The flake blocked #23 and would have blocked others |

### The through-line

Every one of these is the same shape: **something was verified by an artifact
that could not fail.** A gate that scanned zero files and printed OK. A test
whose assertion was `X || string.length > 0`. A guard that passed because the
*test harness* had a resource the *product* did not. A baseline that was
deterministic only because someone had been careful, with nothing asserting the
branch order that made it so.

`BACKLOG.md` "Test-integrity debt" has recorded this shape eight times now, with
the standing rule: **a gate must assert its own subjects exist.** Two refinements
were added this session and are worth carrying forward:

1. **Printing the subject count is not the same as flooring it.** Both gates in
   #21 already printed their count. A reader could see `0` and the exit code was
   still `0`. The count is for humans; the floor is what makes the gate fail.
2. **A zero-floor alone is too weak for a gate that scans more than its own
   subjects.** `check_tree_walks.py` walks the whole repo, so excluding `ui/qml`
   still left 499 files and 17,264 functions scanned — `scanned == 0` sails
   through while the gate is blind to exactly the code it guards. Assert "my
   specific subjects are present", not "something was scanned".

---

## 3. The widget first pass — complete

All 30 widgets audited, 2026-08-03. Method is documented in the audit file
§"Method, per widget"; in short: enumerate every `schema:` key, classify its
strongest existing coverage as **behaviour** / **shape-only** / **absent**,
exercise everything that is not `behaviour`, and fix each finding with a negative
control proving the new assertion fails when the behaviour is removed.

**Why it existed:** `WidgetConfigSchema.qml` opens with the promise *"every
option here is honoured by the corresponding widget — nothing is decorative."*
Nothing verified that. The enumerated-requirements matrix only requires that
*some* assertion mentions a key's leaf token, which a schema-shape test satisfies
completely while proving nothing about the widget.

### Results

35 findings across 30 widgets and 2 shared seams. **All fixed except 2**, both
deliberately filed as Candidates rather than fixed unilaterally.

| Findings | Widgets |
|---|---|
| 0 | `break`, `quote` |
| 1 | `gpu`, `ram`, `net`, `disk`, `packages`, `sinceinstall`, `clock`, `analog`, `moon`, `focus`, `tasks`, `rightnow`, `notes`, `habit`, `hydration`, `meds`, `braindump`, `routine`, `httpjson`, `nownext`, `countdown`, `eod` |
| 2 | `cpu`, `sensors`, `kpi`, `calendar`, `weather` |
| 5 | `media` |

Plus the **NetHub seam** (shared by calendar, weather, nownext, httpjson, kpi and
the update checker): 5 findings, 4 fixed.

### Widget quality assessment

This is a judgement call layered on the audit, not a mechanical result.

**In good shape — no action expected**
`break`, `quote` (clean pass), and the three metric widgets `cpu` / `gpu` / `ram`
after their fixes. `break` is notable: it survived the audit with zero findings
*and* its parked-state behaviour is now pinned (#24).

**Solid, one fix applied, no known residue**
`net`, `disk`, `packages`, `sinceinstall`, `clock`, `analog`, `moon`, `focus`,
`tasks`, `rightnow`, `notes`, `habit`, `hydration`, `meds`, `braindump`,
`routine`, `httpjson`, `nownext`, `countdown`, `eod`.

**Improved substantially this session, worth re-reviewing on device**
- **`weather`** — was "the most basic weather widget ever" (Simon's words). Now
  requests humidity, wind speed + direction, precipitation + probability, UV,
  cloud cover, pressure, sunrise/sunset; renders them as a responsive
  `GridLayout` whose font ceilings scale with the tile's short edge rather than
  flat pixel caps. Two rounds of layout work were needed — the first fix was
  still "tiny with empty space" because the ceilings were flat literals (88/21 px
  on a ~1280×770 tile).
- **`media`** — the only widget with **open findings** (see §4).

**Known weak spot in the shared layer, now covered**
The **NetHub** egress gate had two branches unreachable by construction: product
code excluded tests via `!mk` guards, so the request watchdog and the
response-cap header could never fire in a test. Both fixed by removing the guards
and injecting a fake timer factory. The shared fake XHR also silently swallowed
every header, which is why nobody noticed.

---

## 4. What is NOT done

### 4a. Two open widget findings (filed as Candidates, need a decision)

1. **`"Artwork unavailable"` in MediaWidget can never render, and the case it
   was written for is unhandled.** `MediaWidget.qml:55` reaches that string only
   when `avail && artUrl && !artworkSource.length` *and* `remoteArtworkBlocked`
   is false — but those three conjuncts *are* the definition of
   `remoteArtworkBlocked` at `:53`. Dead by algebra.
   The live gap it was presumably meant to cover: a `file://` artwork that passes
   the policy but fails to **load** (deleted, unreadable, corrupt) leaves
   `artworkSource` non-empty, shows no notice, and draws a silently blank art
   box. Wiring the rung to the `Image`'s `status === Image.Error` makes it both
   reachable and correct. Small, user-visible, testable — the artwork policy
   already has ten cases to extend. Audit finding 10.4.

2. **A dead `notificationBridge.send` fallback in three widgets.**
   `FocusWidget.qml:241`, `BreakWidget.qml:194`, `MedsWidget.qml:297` each fall
   back to `send()` when the bridge has no `sendPriority()`. There is exactly one
   real bridge and it implements `sendPriority`; both test doubles do too. Dead
   in production *and* in tests, three times over. Unlike a version-skew fallback
   it cannot become reachable — QML and the C++ bridge ship in one binary from
   one qrc. Either delete all three (keeping the outer `&& .send` guard, which
   still usefully covers "no bridge injected"), or keep them and give one double
   no `sendPriority`. **Wants a single decision, not three.** Audit finding N.5.

### 4b. Blocked on Simon

| # | Decision | Status |
|---|---|---|
| D1 | Calm default theme | **DECIDED 2026-08-04 — already shipped.** Default is `nord`, the calm palette. See §6. |
| D2 | Default font | **DECIDED 2026-08-04 — already shipped.** Atkinson Hyperlegible. |
| D3 | Lawyer pass on distro theme naming | **OPEN.** Partly de-risked: `Theme.qml:334` keeps distro modes colour-only, no logos or wordmarks. The *naming* is the residual exposure. This is sold B2B. |
| D4 | Payment provider | Decided (Lemon Squeezy / Gumroad). **Two Simon-only steps remain** — see below. |

**Licensing, remaining Simon steps** (the system is built and CI-verified):
1. Run `cargo run --manifest-path tools/license-tool/Cargo.toml -- keygen` once;
   paste the public key into `core/src/license.rs`; store the private seed in
   Bitwarden. **Until this is done, every key verifies as free.**
2. Create the Lemon Squeezy / Gumroad product and wire key delivery.

**New question raised 2026-08-04, not yet answered:** should the per-widget
`behaviorProfile` default to `calm` instead of `custom` — i.e. no celebrations,
reward points or nudges out of the box? This is the *other* plausible reading of
"calm by default", it is a real behaviour change rather than a palette, and it
was never asked. Only `focus` and `tasks` have this key.

### 4c. Open engineering gaps (no decision needed, just work)

- **W3 — widget smoothness needs Simon's eyes on the panel.** All the motion work
  landed (Sensors delegate churn, Dashboard and EdgeClone reorder teleports,
  PillButton glyph scaling, add/remove fades). None of it is verified on the real
  device because the offscreen harness cannot instantiate `qrc:` widgets —
  delegate survival is asserted via the Loader, not the widget. **This is the one
  W-item that genuinely needs a human looking at the screen.**
- **`backup_config()` is still only reached via `--reset`.** `config.toml.bak`
  is never written by a normal save, so the "canonical good-config backup" is not
  a routine safety net. Worth deciding whether a save should ever produce one.
- **AppImage zsync update path has never worked and has never run.** Still an
  **RC exit criterion**. No release has ever shipped an AppImage or a `.zsync`.
  Two fixes landed (version-from-CMake trap, `fetch-depth: 0` so `git describe`
  can produce a SemVer-comparable version). **Still open and needing a product
  decision:** the AppImage embeds no `X-AppImage-UpdateInformation`, so
  `AppImageUpdate`/`appimaged` cannot update it at all and there is no discovery
  path from an installed AppImage to the next `.zsync`.
- **Wallpaper/theme name collision — it is FIVE names, not three.** Measured
  overlap: `aurora`, `ember`, `midnight`, `nebula`, `sunset`. The nuance before
  anyone "fixes" it: `WallpaperCatalog.qml`'s header says the wallpapers are
  "tuned to the built-in themes", so a shared name may be a deliberate *pairing*.
  But only 5 of 12 wallpapers match a theme and 19 of 24 themes have no
  wallpaper, so it reads as a systematic pairing that is not one. Renaming either
  set rewrites persisted config and needs a migration — **the cheap fix is UI
  disambiguation plus honest copy. Decide the intent first; it is a copy
  question, not an engineering one.**
- **`build-release/` is tracked in git — 196 files of build output.** Found
  2026-08-04. Not cleaned because it is a large deletion that wants approval.
- **`scripts/test.sh` is still the framework adoption stub** — it echoes "No test
  command configured" and exits 0. Under the evidence policy it must never be
  cited as passing validation.

---

## 5. Findings from online research

**None. No web research was performed in this session or the preceding widget
audit sessions.** Everything recorded in the audit and in `BACKLOG.md` was
derived from reading this repository's own source, tests, CI logs and git
history, and from running the suites locally.

This is stated explicitly because the handover was asked to include such a
section, and inventing findings would be worse than reporting the absence. If
external input is wanted, the areas where it would genuinely help are:

- **Open-Meteo API surface** — the weather widget now consumes ten fields; a
  review of what else the free tier offers (air quality, pollen, minutely
  precipitation) could inform the next weather pass.
- **MPRIS edge cases across players** — the D-Bus fan-out is deliberately left
  to on-device E2E and is `GCOVR_EXCL`'d with that reason. Real-world player
  quirks are exactly the kind of thing documentation would shortcut.
- **AppImage update information conventions** — the `X-AppImage-UpdateInformation`
  decision above would benefit from seeing how comparable projects wire zsync
  discovery.
- **Comparable dashboard products** — for the "what should a screen surface"
  question in §7. No competitive scan has been done.

---

## 6. Two things the backlog got wrong (read this before trusting an entry)

`BACKLOG.md`'s own header says: *"If an entry here disagrees with the code, the
code wins."* That is not a formality. **Five items closed on 2026-08-04 were
stale entries describing problems that were already fixed:**

- **D1** claimed "current default: dark". Both layers default to `nord`
  (`core/src/config.rs:173`, `ui/qml/Theme.qml:362`), and the Rust test pinning
  it has read *"shipped default is the calm palette (D1)"* since it was written.
  The `mode = "dark"` at `config.rs:1847` that looks like a default is a **legacy
  test fixture**.
- **D1** also asked for "calm as the default theme". **There is no `calm`
  theme.** `calm` is a per-widget `behaviorProfile`. The backlog had already
  recorded this discovery elsewhere without reconciling the D1 row.
- **D2** was already implemented (`Theme.qml:235`).
- **"CI has a font blind spot"** described `fontMono` resolving through
  fontconfig. It has been bundled since 2026-08-02.
- **`preset-health` "STILL FRAGILE"** was fixed **in the same PR that filed the
  entry** (#13).

**Recommendation for the next session:** a periodic reconciliation pass over
`BACKLOG.md` against the tree is worth more than working entries at face value.
In every one of the five cases the *real* work was underneath — an invariant that
nothing asserted — and would have been missed by either believing the entry or
ignoring it.

---

## 7. What would be better functionality (product ideas, unapproved)

Ordered by how much they would change the product, not by effort.

1. **Surface a screen when something on it becomes noteworthy.** The shipped
   auto-cycle takes turns on a clock. The interesting version reacts to content:
   a threshold crossed, a calendar event imminent, a break due, a countdown
   expiring. The repository already has the vocabulary — widget `state` /
   `Warning` / `Critical`, and a priority-alert GUI suite. This would make the
   other screens *earn* attention instead of merely taking turns. The idle
   rotation was the cheap half. **Needs a product decision, not a setting.**
2. **Make `--reset`'s backup a routine safety net** rather than a reset-only
   artifact (see §4c). Users lose layouts; a `.bak` written on every successful
   save is cheap insurance.
3. **Media artwork error state** (§4a item 1) — small, visible, and the widget
   currently draws a silently blank box for a broken file.
4. **A premium preset pack and/or custom user widgets** as Pro-gated content. The
   flag infrastructure is one line; it needs a "which items" decision. Currently
   Pro gates a theme pack only.
5. **Weather, next pass** — the widget is now genuinely informative but still
   shows one location. Multi-location, or a "conditions changed materially"
   highlight, would suit a wall panel.

---

## 8. Traps that cost real time (do not re-pay these)

**Testing**
- **The QML harness loads widgets from `qrc:`.** A product edit proves nothing
  until `xeneon-qmltestrunner` is rebuilt. This invalidated four negative
  controls in a row during the weather work. `run_ui_tests.sh` has a stale-runner
  guard; a manual `-input` run does not.
- **But `tst_theme.qml` imports `"../../ui/qml"` as a FILESYSTEM path**, so its
  font loaders read `assets/fonts/` off disk and never touch the qrc. Sabotaging
  `fonts.qrc` leaves it green. The two facts above coexist; know which file you
  are in.
- **A control that does not apply looks exactly like a control that does not
  bite.** Two sabotage attempts silently no-op'd on 2026-08-04 (a `sed` that
  matched nothing; a Python edit that broke syntax instead of the regex). Always
  assert the sabotage landed before drawing a conclusion.
- **`test_x_data()` is QtTest's data provider for `test_x()`.** Three tests had
  never executed. `scripts/check_live_tests.sh` gates this now.
- **Never bound test memory with the kernel OOM killer.** Use `ulimit -v` plus an
  RSS watchdog. And never write a test that maxes CPU/GPU/RAM — this crashed
  Simon's machine once. Boundary tests are fine; hammering is never fine.

**Tooling**
- **`pkill -f <pattern>` kills the invoking shell** (the Bash tool's command line
  contains the pattern) → exit 144, script dies mid-way. Use `kill` by PID from a
  prior `pgrep`, or a bracket class (`"[g]h pr checks"`).
- **`pkill -x <name>` silently matches nothing when the name exceeds 15 chars.**
  `xeneon-edge-manager` is 19 — the command reports success having done nothing.
  `xeneon-edge-hub` is exactly 15 and works, which makes the failure look
  inconsistent.
- **`visual_baselines.py update` rewrites ALL fifty baselines**, not the one you
  changed — which its own docstring forbids. Re-capture the single case through
  `write_normalized` and patch that one manifest entry; the diff should be one
  PNG and three manifest fields.
- **`scripts/gen_widgets.py` is stale bootstrap scaffolding, not a source of
  truth.** `--force` would replace a real widget with a 20-line stub. It did,
  once, to `RamWidget`.
- **Committing on `master` and pushing a branch ref merges nothing.** PR #19
  appeared to merge and did not; recovered from reflog. Verify the branch
  actually carries the commit before opening the PR.

**Product**
- **Single-writer rule:** a running `xeneon-edge-manager` re-pushes its UI state
  to the hub on hub start, silently reverting direct `config.toml` edits. Stop
  the Manager before editing config by hand.
- **Wayland window placement:** position and `setScreen` *before*
  `showFullScreen`/`show`, or the compositor picks the wrong display.

---

## 9. How the backlog is organised

Sections are load-bearing under the scope-control policy:

- **Blocked on Simon** — nothing downstream proceeds.
- **Beta workstreams / Known gaps / v1.1 / Test-integrity debt** — approved work.
  An agent may pick these up autonomously.
- **Candidates** — unapproved. **Never implemented without explicit product-owner
  approval.** Findings from any work go here, not into the code.

---

## 10. Restarting cold — suggested first moves

1. Read `AGENTS.md`, then this file, then `BACKLOG.md`'s section headings.
2. `./scripts/run_all_tests.sh` for a full picture, or the focused gates for a
   quick one. Everything was green at handover.
3. **Reconcile before building.** Given §6, spot-check any backlog entry against
   the tree before working it.
4. If continuing the productive thread: the test-integrity work has found a real
   defect every time it has been run, and its own open follow-up is that *nothing
   forces the fail-on-violation proof for new guards*. The proposed fix — require
   a guard's sabotage evidence in the PR body — is currently convention, not a
   gate. Making it enforceable is a scoped, valuable next item.
5. If Simon is available: D3, the two licensing steps, the `behaviorProfile`
   question, and the AppImage update-information call unblock more than any
   amount of further hardening.
