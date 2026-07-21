# Overnight Execution Report

_2026-07-16 → 2026-07-17. Baseline `3625dd5` → `7c3a01b`+ (master and `v1.0-alpha`
in lockstep, both pushed). 17 non-merge commits._

## Summary

The session began by verifying one sentence from a Wave-3 agent's report - *"a
test now fails if the URL ever grows one"* - and that single thread unravelled a
consistent theme: **several of this repo's guarantees were asserted by things
that could not fail.** Wave 3 (the sizing epic's last five widgets) is merged and
pushed. The four beta workstreams W2/W3/W4 landed. Along the way I found and
fixed a red CI job nobody had noticed, a vulnerability-reporting address at an
unregistered domain, 202 MB of committed build output, a nightly test flake, and
an unrecoverable data-loss path in `--reset`.

**Status: green, and now verified.** Full suite `RESULT: SUCCESS` (17 suites incl.
9 runtime E2E scenarios), behavior matrix 100%. CI on the final tree (`ff13cad` /
`5ddbf49`) is **green on every job**: Rust (fmt+clippy+test), Build, QML +
behavior matrix, C++ + coverage, the Rust+C++ ≥95% coverage gate, SBOM,
cargo-deny, the no-egress attestation (with its three negative controls), and
Docs. The `gh` outage that blocked this for part of the night cleared.

## Completed work

### The thread: three tests had never run
`WeatherWidget`'s egress guard was inert. Injecting `&hourly=temperature_2m` into
the request left the suite **green**. Cause: QtTest silently treats `test_X_data()`
as the *data provider* for `test_X()`. The guard was named
`test_the_request_never_asks_for_hourly_data()`, so it became the provider for a
test that never existed and ran as neither. No warning.

A sweep found **three** such tests, two predating Wave 3. One (`test_seed_shapes_data`)
**failed the moment it could run** - its expectations were stale since the preset
re-authoring split gaming/productivity into three pages. Nobody noticed, because
it never ran. `scripts/check_live_tests.sh` now gates the class in CI and locally.

### Real defects found and fixed (none of these were on the backlog)
| What | Why it mattered |
|---|---|
| **`security@xeneon-edge-hub.dev` was unregistered** - no A record, no MX | The only documented way to report a vulnerability in a public, sold, AUR-published product. Reports bounced; **anyone could have registered the domain and received private 0-day reports.** Now GitHub private vulnerability reporting (enabled), which cannot be squatted. |
| **Docs CI was RED on master** for two runs | The link was *valid*; the checker tested `file.md#anchor` as a filename. A gate that cries wolf gets ignored - which is how the dead security contact survived in the same file. |
| **`--reset` destroyed the layout with no backup** | One word from `--reset-wizard`, which keeps it. `backup_config_of()` - "the canonical good-config backup" - existed, was tested, and was called by **nothing but a test**: `config.toml.bak` was never produced in production. |
| **202 MB / 507 files of makepkg output committed** | `packaging/aur/` never got the `.gitignore` `packaging/local/` has had since birth; the root rules name `packages/**`, a *different* real directory. Included two ~4 MB binaries. |
| **Local dogfood build versioned BELOW the release** | `vercmp 0.1.0.r218 1.0.0alpha.2` = **-1**. `pacman -U` called a fresh build a downgrade, and the next `yay -Syu` would have **silently reverted Simon to alpha.2** - looking exactly like "my changes did nothing". Now tag-derived. |
| **`tst_meds` failed nightly, 00:00–00:10** | `hhmm(-10)` formats a bare `HH:mm`: ten minutes before 00:07 is `23:57`, which the widget correctly reads as due *later today*. The test said "in 23h50m" and meant "ten minutes ago". Hit live at 00:07 CEST. |
| **A stranded manager fix, never merged** | A real Fusion `implicitWidth` binding-loop fix sat unmerged on a stray worktree branch. Recovered before cleanup deleted it. |
| **`cargo audit` claimed to run "on every commit"** | It runs nowhere - deleted during the Actions-quota cut. SECURITY.md also claimed keyring secret storage (parked) and listed 0.1.x as the supported version (shipped: 1.0.0-alpha.2). |

### Beta workstreams
- **W3 - reorder teleport (merged).** Two nested causes; the **page** Repeater was
  dominant - every page, tile and live widget was destroyed for a single tile move,
  so fixing the tile Repeater alone would have changed nothing. Ease now lives on
  the *semantic slot*, so a structure edit glides while a rotation stays instant -
  no flag, no timer.
- **W3 - PillButton / Habit `1x1.5` (merged).** Emoji have zero bearing (ink *is*
  the box) and the glyph was frozen at a literal `18` - the 1.2× ratio frozen at
  textScale 1.0. Habit's `1x1.5` accepted with a transposed 4×7 map.
- **W4 - runtime E2E 6 → 9 scenarios (merged).** `--reset` flags, live-push
  single-writer over the real socket, page-dedup round-trip.
- **W2 - Manager clarity (merged).** Audit written (`docs/ux/manager-audit-2026-07-16.md`).
  Found a **silent data-loss bug**: a typed page name was destroyed because nothing
  in the pane takes focus. Fixed scope-pill contradictions and copy that promised a
  preview two sections away from where it was true.

### Housekeeping
37 stale worktree branches removed (**26 GB**); repo left with exactly `master`
and `v1.0-alpha`, local and remote. `BACKLOG.md` created - open items had been
split across BETA_PLAN (strategy) and SESSION_HANDOFF (log), so "what is left?"
had no single answer.

## Tests

- Full suite green: Rust, QML, C++ (20/20), behavior matrix **100%**, egress lint,
  live-test lint (new), doc links (new), icon lint, **9** runtime E2E scenarios.
- **Every agent proved fail-on-violation**, and the discipline paid: the W4 agent's
  own sabotages caught **two of its own tests** that could not fail; the W3 agent
  **disproved its own comment** about reduce-motion and corrected it; the small-fixes
  agent found a test asserting a *property* rather than the rendered value.
- I verified agents rather than trusting them: I re-ran the dedup sabotage myself.
  It "passed" - because runtime scenarios drive the **real binary** and QML is baked
  in via `qrc`, so a `.qml` edit is inert until a rebuild. After rebuilding it failed
  loudly. **A sabotage that does not change the binary tests the old binary** - now
  documented, because the false conclusion ("this guard is inert") invites deleting
  a guard that works.

## Newly identified tasks (in `BACKLOG.md`)

- **`--reset` had no backup** → fixed. But **the good-config `.bak` is still only
  written by reset**; nothing else calls `backup_config()`.
- **Manager half of the single-writer rule is unproven end-to-end** (the hub half now
  is). The Manager saves only via GUI and exposes no headless hook.
- ~~`manager/qml/EdgeClone.qml` array-model rebuild~~ - **CONFIRMED and FIXED**
  (`43f55eb`). The premise was proven before the fix, with an identity guard run
  against the unfixed code (`TELEPORT PROOF ... returned FALSE`). It also turned up
  a latent bug nobody was looking for: `targetAt` returned a ROW number bridged
  through `placements[from].idx`, which is correct only until the first drag
  reorders something. Seven guards, each proven red on violation.
- Wallpaper/theme **name collision**: Midnight/Nebula/Aurora are each both a theme
  and a wallpaper.
- About's GitHub button opens `"#"` and does nothing (needs a real URL).
- `HydrationWidget.qml:260` hard-codes `PillButton { implicitWidth: 170 }`, defeating
  content-derived sizing; will break at textScale 1.6.
- AppImage zsync update path still never exercised end-to-end (an **RC exit criterion**).

## Issues and blockers

- ~~CI for the final HEAD is unverified~~ - **RESOLVED before hand-off.** For part
  of the night every Actions API call returned 503 while githubstatus reported
  Actions operational and `git` over SSH kept working; `gh auth status` said the
  keyring token was invalid, though earlier `gh` calls in the same session had
  succeeded. It cleared on its own. Every job is green on the final tree (listed
  in Summary). Worth knowing the failure mode: **a broken local token presents as
  a GitHub outage**, and the honest read is "I cannot see CI", not "CI is fine".
- **Secret scanning + push protection could not be enabled** - the repo-settings API
  call was blocked by the permission classifier, correctly. Both are free on public
  repos and currently **disabled**; enabling push protection is a one-click item and
  is the thing that stops a secret from ever landing in a commit.
- **Repo history still carries the 202 MB** of build output. Removing it needs a
  history rewrite, which I will not do unilaterally on a published repo.
- **Four owner decisions still block the beta** (unchanged): Calm as default theme,
  default font, lawyer pass on distro theme naming, payment provider.
- **`--reset` backup policy is a decision, not a bug fix, if you disagree with it.**
  I implemented "always back up, and refuse to reset if the backup fails". If you
  intend `--reset` to mean "destroy it, I'm sure", say so and I'll revert.

## Stability assessment

**Usable, and materially safer than at session start.** The three inert tests, the
unregistered security contact, the silent `yay -Syu` revert, and the `--reset` data
loss were all live risks in shipped or shipping code. Remaining risk is concentrated
in what is *not* proven rather than what is broken: the Manager's half of the
single-writer rule, the AppImage update path, and CI on the final commit.

## Next recommended actions

1. **Install the build** (below) and confirm the reorder animation + Manager clarity
   on the real Edge - W3/W2 are verified offscreen; the harness cannot instantiate
   `qrc:` widgets, so widget-instance survival is asserted via the Loader only.
2. ~~Verify CI~~ - done, all jobs green on `ff13cad`/`5ddbf49`. Nothing needed.
3. **Enable secret scanning + push protection** (Settings → Code security). Both
   are free on public repos and currently off; the API call to enable them was
   blocked by the permission classifier, correctly - it is yours to click.
4. **Make the four beta decisions** - they gate feature freeze.
5. ~~Port the `animS/animL` pattern to `EdgeClone.qml`~~ - done (`43f55eb`); verify the glide on the real device, which no offscreen harness can show.
6. Decide the `--reset` backup policy.

### Install

```
sudo pacman -U /home/simon/IdeaProjects/XeneonEdge_Linux/packaging/local/xeneon-edge-hub-1.0.0.alpha.2.r83.g6885b80-1-x86_64.pkg.tar.zst
```

`sudo` is not passwordless here, so this is yours to run. It is a genuine **upgrade**
over the installed `1.0.0alpha.2-1` (`vercmp` = 1) - before this session it would
have been a downgrade. Restart the hub with **SIGTERM, never SIGKILL** (it saves
config on the way out), or just run `./scripts/update-local.sh`, which does the
build, the install and the graceful restart in one step.

---

## Addendum - 2026-07-17 daytime (continued autonomous pass)

Worked the remaining backlog. Everything below is merged, pushed, and green on
all four workflows.

**The AppImage self-update path never worked, and had never run.** Not "untested"
- unexecuted. No release ever published an AppImage (`gh release view` on alpha.1
and alpha.2 confirms it), so `release.sh`'s `zsyncmake` branch has executed zero
times. Two independent bugs underneath: the artifact was named from
`project(... VERSION 0.1.0)`, which CMake freezes, so every release forever would
have shipped an identically-named `xeneon-edge-hub-0.1.0-x86_64.AppImage`; and
`build-appimage.sh` never passed `-DXENEON_VERSION_OVERRIDE`, so the version came
from `git describe --tags` while `actions/checkout` fetches **no tags** at depth 1
- `--always` then silently degrades to a bare sha, which `UpdateChecker` cannot
SemVer-order. The one install kind pointed at zsync could never have detected an
update. CI now produces `xeneon-edge-hub-1.0.0-alpha.2-101-g69a0484-x86_64.AppImage`
and that string parses. **Still open (your decision):** no
`X-AppImage-UpdateInformation` is embedded, so there is no discovery path from an
installed AppImage to the next `.zsync`. That defines a public URL contract.

**The born-inert audit - eight instances, one shape.** A gate reports SUCCESS for
the state where it did no work.

| Gate | How it was inert |
|---|---|
| 3 QtTest cases | `test_x_data()` = data provider for a `test_x()` that never existed |
| `coverage.sh` C++ gate | gcovr arg misparse → `n/a` → the gate skipped **itself**, for years |
| `qml_coverage.py` | empty matrix scored **100%**; a typo'd source dropped 24 behaviors with *no* coverage drop |
| `check_ui_links.sh` (mine) | grepped a pattern that was line-wrapped in its own target |
| `check_live_tests.sh`, `check_doc_links.sh` (mine) | reported OK on an **empty tree** |
| `packaging/ci/smoke.sh` | zero derived modules → loop ran zero times → SMOKE PASS |
| a W3 agent's guard | mode-keyed literal only fires with the mode ON; its hosts were `expanded:false` |

All fixed. The fix is always the same, and `check_no_raw_xhr.sh` had it right from
the start: **a gate must assert its own subjects exist.** Its one line - "the gate
must still own exactly one construction site" - is why the no-telemetry claim rests
on something. I verified that lint both directions while auditing.

**Consequence worth flagging: C++-only coverage is 91.70%, not 95.** That number
was never enforced because the gate never ran. It is now a ratchet at the measured
floor. CI is unaffected (it gates Rust ≥95 AND merged ≥95, never C++-only).

**Also landed:** the Manager's About button opened `"#"` and did nothing (fixed +
linted); `mpris_bridge.cpp` was not at 0% coverage but *invisible to coverage
entirely* - 279 lines in nobody's denominator - now extracted and covered without
a bus; the Dashboard and EdgeClone both gained exit fades, entrances and eased add
slots; Hydration/Habit stopped conflating `expanded` with size.

**A real bug found while porting the fade to EdgeClone:** a dying row's `tileIdx`
is stale, so a drop onto a fading tile would have silently moved the **wrong
widget**. Now guarded; I reproduced the guard's failure myself.

### Still open for you
1. `X-AppImage-UpdateInformation` - a public URL contract (above).
2. The four beta decisions (Calm default, font, distro-name legal pass, payments).
3. Secret scanning + push protection - a click in Settings → Code security.
4. **Nothing motion-related is verified on the real panel.** The offscreen harness
   cannot instantiate `qrc:` widgets, so every agent asserted Loader survival and
   said so plainly. This genuinely needs your eyes on the device.
5. The `expanded`-vs-size conflation remains in 7 more widgets (see `BACKLOG.md`).

### Install
```
sudo pacman -U packaging/local/xeneon-edge-hub-1.0.0.alpha.2.r110.gd926d41-1-x86_64.pkg.tar.zst
```
`sudo` is not passwordless here, so this is yours. It is a genuine upgrade
(`vercmp` = 1) over the installed `1.0.0alpha.2-1`.

---

## Addendum 2 - 2026-07-17 evening (backlog drawdown)

Worked the actionable backlog to the point where what remains is genuinely
yours to decide. All merged, pushed, four workflows green.

**The `expanded`-vs-size conflation is closed across all 7 remaining widgets**
(EndOfDay/Focus/Moon/RightNow, Net/Tasks/Hydration), after Habit. Each mode-keyed
*size* now derives from the actual box; genuine mode-checks (a header, an
editor-vs-display split, which side peaks sit on) were kept and documented; dead
`expanded` terms were removed. Two celebrate labels gained the missing
wrapMode/elide. The agents documented two *honest* non-guards - sizes where the
literal and the derived formula land on the same cap, so no test can tell them
apart - rather than ship green-either-way guards.

**A latent gauge overflow, and the sweep it triggered.** The RAM gauge's centre
reading overran its ring when `theme.fontMono` fell back to a proportional face -
`Layout.maximumWidth` is inert once implicitWidth exceeds it, taking HorizontalFit
and elide down with it. Same fix as CountdownWidget: pair `preferredWidth`. A
sweep found the identical shape at three more real sites (Kpi/Clock/Break, all
fixed) and one non-issue (a wrapping Text, which binds the cap on its own). No
automated guard for these: I wrote one, my own negative control passed (the value
pre-fits by char count under a mono font), so it was inert - removed it rather
than ship it. Verified manually under a no-mono fontconfig; the CI font blind spot
is recorded.

**Two stale backlog entries corrected against the code** (the drift this whole
session has been about): the Manager half of the single-writer rule is NOT
unproven - `connectedSaveIsIpcOnlyNoFileWrite` already asserts
`!QFile::exists(config.toml)` after a connected save, and I verified it reds on
violation (1/21) and greens on restore (21/21). And `motionRemove` is no longer
unused - the exit-fade work wired it in.

**A real footgun neutralised: `scripts/gen_widgets.py` silently overwrote
hand-written widgets.** It bit me directly - an accidental run clobbered
RamWidget.qml (mid-gauge-fix) and littered stale stubs. It now writes nothing by
default (skips existing files and dead names; `--force` to override), and
AGENTS.md's "re-run to regenerate" advice - which was the footgun's instruction
manual - is corrected.

### What is left, and why I did not do it
- **Decisions only you can make:** the wallpaper/theme naming (is Midnight-the-
  wallpaper meant to pair with Midnight-the-theme? - five names collide); the
  AppImage `X-AppImage-UpdateInformation` URL contract; whether a normal save
  should refresh `config.toml.bak`. Each changes user-facing behaviour or public
  contracts; not mine to pick.
- **Tracked, non-blocking:** C++-only coverage is 91.70% (a ratchet, improves as
  logic is extracted); the CI font blind spot (a proportional-fallback overflow
  can't reproduce under CI's DejaVu-mono). Both recorded in BACKLOG.md.

### Install
```
sudo pacman -U packaging/local/xeneon-edge-hub-1.0.0.alpha.2.r122.g1335087-1-x86_64.pkg.tar.zst
```
`sudo` isn't passwordless here, so this is yours. Genuine upgrade (`vercmp` = 1).

---

## Addendum 3 - 2026-07-17 late (backlog drained to decisions)

This pass took the backlog down to what genuinely needs *you* - I stopped rather
than manufacture work or make product calls unilaterally.

**The Hydration overlay overflow is fixed** (`67052c6`). It was real, not
speculative: measured 612px (goal 8) / 812px (goal 20) of fixed literals spilling
off both ends of the 456px preview pane *and* off the real device's 720px
landscape screen at goal ≳12 - the count clipped off the top, the goal controls
off the bottom (unreachable). Now room-derived (an `ovlScale` from the box height
plus a closed-form area budget for the glass grid, so 20 glasses fill columns
instead of a taller stack). Portrait keeps its generous look. The agent caught a
subtlety my own reproduction missed - the real overlay sets `showHeader=false`, so
the guard measures the true on-device room. I independently re-verified the guard
reds on violation (reverting count+cell to literals → top=-9 on the pane, -26 on
the device).

**Two stale backlog entries corrected against the code:** the EdgeClone
exit/entrance "still pops" note (closed in `b7c023f`), and the Manager single-
writer "unproven" note (it's proven by `connectedSaveIsIpcOnlyNoFileWrite`, which
I confirmed reds on violation).

**`path_sanitize.h`'s one uncovered line documented honestly** (`7abb6ee`). It was
the path-traversal *reject* branch, unreachable because `fileName()` normalizes
first - verified by the existing traversal matrix. Rather than fake a test that
can't reach it, it's `GCOVR_EXCL_LINE` with a comment saying it's defense-in-depth
retained against that normalization ever weakening. 100% of reachable lines now.

### What is left - and none of it is mine to decide
- **Decisions:** D1–D4 (Calm default, font, distro-name legal pass, payments);
  the wallpaper/theme naming intent (is Midnight-the-wallpaper meant to pair with
  Midnight-the-theme?); the AppImage `X-AppImage-UpdateInformation` URL contract;
  whether a normal save should refresh `config.toml.bak`.
- **Needs the physical panel:** W5 persona walkthroughs, and confirming the motion
  work (reorder/fade/entrance in Dashboard + EdgeClone, the Hydration overlay) -
  the offscreen harness can't instantiate `qrc:` widgets, so every fit/motion
  guard asserts mapped geometry or Loader survival, never the rendered widget.
- **Needs tooling absent here:** the AppImage download-and-patch round trip (needs
  `zsync` + a buildable AppImage; linuxdeploy's `strip` can't read this host's
  `.relr.dyn`).
- **Tracked, non-blocking, diminishing returns:** C++-only coverage (91.5%,
  ratchet 91; the remaining gaps are Qt socket/GUI glue, much already GCOVR_EXCL);
  the CI font blind spot (a proportional-fallback overflow can't reproduce under
  CI's DejaVu-mono - closing it means either CI cost you're quota-sensitive about
  or test-infra whose only payoff is regression-prevention on an already-fixed
  class; flagged rather than decided).

### Install
```
sudo pacman -U packaging/local/xeneon-edge-hub-1.0.0.alpha.2.r128.g9633501-1-x86_64.pkg.tar.zst
```
`sudo` isn't passwordless here, so this is yours. Genuine upgrade (`vercmp` = 1).
