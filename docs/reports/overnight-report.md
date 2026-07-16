# Overnight Execution Report

_2026-07-16 → 2026-07-17. Baseline `3625dd5` → `7c3a01b`+ (master and `v1.0-alpha`
in lockstep, both pushed). 17 non-merge commits._

## Summary

The session began by verifying one sentence from a Wave-3 agent's report — *"a
test now fails if the URL ever grows one"* — and that single thread unravelled a
consistent theme: **several of this repo's guarantees were asserted by things
that could not fail.** Wave 3 (the sizing epic's last five widgets) is merged and
pushed. The four beta workstreams W2/W3/W4 landed. Along the way I found and
fixed a red CI job nobody had noticed, a vulnerability-reporting address at an
unregistered domain, 202 MB of committed build output, a nightly test flake, and
an unrecoverable data-loss path in `--reset`.

**Status: green.** Full suite `RESULT: SUCCESS` (17 suites incl. 9 runtime E2E
scenarios), behavior matrix 100%, all four GitHub workflows green as of `80352d3`.
CI for the final commits is **unverified** — the local `gh` token went invalid
mid-session, so I could not read the Actions API. That is a local auth problem,
not a CI or tree problem (`git` over SSH kept working). See Blockers.

## Completed work

### The thread: three tests had never run
`WeatherWidget`'s egress guard was inert. Injecting `&hourly=temperature_2m` into
the request left the suite **green**. Cause: QtTest silently treats `test_X_data()`
as the *data provider* for `test_X()`. The guard was named
`test_the_request_never_asks_for_hourly_data()`, so it became the provider for a
test that never existed and ran as neither. No warning.

A sweep found **three** such tests, two predating Wave 3. One (`test_seed_shapes_data`)
**failed the moment it could run** — its expectations were stale since the preset
re-authoring split gaming/productivity into three pages. Nobody noticed, because
it never ran. `scripts/check_live_tests.sh` now gates the class in CI and locally.

### Real defects found and fixed (none of these were on the backlog)
| What | Why it mattered |
|---|---|
| **`security@xeneon-edge-hub.dev` was unregistered** — no A record, no MX | The only documented way to report a vulnerability in a public, sold, AUR-published product. Reports bounced; **anyone could have registered the domain and received private 0-day reports.** Now GitHub private vulnerability reporting (enabled), which cannot be squatted. |
| **Docs CI was RED on master** for two runs | The link was *valid*; the checker tested `file.md#anchor` as a filename. A gate that cries wolf gets ignored — which is how the dead security contact survived in the same file. |
| **`--reset` destroyed the layout with no backup** | One word from `--reset-wizard`, which keeps it. `backup_config_of()` — "the canonical good-config backup" — existed, was tested, and was called by **nothing but a test**: `config.toml.bak` was never produced in production. |
| **202 MB / 507 files of makepkg output committed** | `packaging/aur/` never got the `.gitignore` `packaging/local/` has had since birth; the root rules name `packages/**`, a *different* real directory. Included two ~4 MB binaries. |
| **Local dogfood build versioned BELOW the release** | `vercmp 0.1.0.r218 1.0.0alpha.2` = **-1**. `pacman -U` called a fresh build a downgrade, and the next `yay -Syu` would have **silently reverted Simon to alpha.2** — looking exactly like "my changes did nothing". Now tag-derived. |
| **`tst_meds` failed nightly, 00:00–00:10** | `hhmm(-10)` formats a bare `HH:mm`: ten minutes before 00:07 is `23:57`, which the widget correctly reads as due *later today*. The test said "in 23h50m" and meant "ten minutes ago". Hit live at 00:07 CEST. |
| **A stranded manager fix, never merged** | A real Fusion `implicitWidth` binding-loop fix sat unmerged on a stray worktree branch. Recovered before cleanup deleted it. |
| **`cargo audit` claimed to run "on every commit"** | It runs nowhere — deleted during the Actions-quota cut. SECURITY.md also claimed keyring secret storage (parked) and listed 0.1.x as the supported version (shipped: 1.0.0-alpha.2). |

### Beta workstreams
- **W3 — reorder teleport (merged).** Two nested causes; the **page** Repeater was
  dominant — every page, tile and live widget was destroyed for a single tile move,
  so fixing the tile Repeater alone would have changed nothing. Ease now lives on
  the *semantic slot*, so a structure edit glides while a rotation stays instant —
  no flag, no timer.
- **W3 — PillButton / Habit `1x1.5` (merged).** Emoji have zero bearing (ink *is*
  the box) and the glyph was frozen at a literal `18` — the 1.2× ratio frozen at
  textScale 1.0. Habit's `1x1.5` accepted with a transposed 4×7 map.
- **W4 — runtime E2E 6 → 9 scenarios (merged).** `--reset` flags, live-push
  single-writer over the real socket, page-dedup round-trip.
- **W2 — Manager clarity (merged).** Audit written (`docs/ux/manager-audit-2026-07-16.md`).
  Found a **silent data-loss bug**: a typed page name was destroyed because nothing
  in the pane takes focus. Fixed scope-pill contradictions and copy that promised a
  preview two sections away from where it was true.

### Housekeeping
37 stale worktree branches removed (**26 GB**); repo left with exactly `master`
and `v1.0-alpha`, local and remote. `BACKLOG.md` created — open items had been
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
  It "passed" — because runtime scenarios drive the **real binary** and QML is baked
  in via `qrc`, so a `.qml` edit is inert until a rebuild. After rebuilding it failed
  loudly. **A sabotage that does not change the binary tests the old binary** — now
  documented, because the false conclusion ("this guard is inert") invites deleting
  a guard that works.

## Newly identified tasks (in `BACKLOG.md`)

- **`--reset` had no backup** → fixed. But **the good-config `.bak` is still only
  written by reset**; nothing else calls `backup_config()`.
- **Manager half of the single-writer rule is unproven end-to-end** (the hub half now
  is). The Manager saves only via GUI and exposes no headless hook.
- `manager/qml/EdgeClone.qml` very likely has the **identical array-model rebuild**
  the W3 agent fixed in `Dashboard.qml` — the clone probably still teleports.
- Wallpaper/theme **name collision**: Midnight/Nebula/Aurora are each both a theme
  and a wallpaper.
- About's GitHub button opens `"#"` and does nothing (needs a real URL).
- `HydrationWidget.qml:260` hard-codes `PillButton { implicitWidth: 170 }`, defeating
  content-derived sizing; will break at textScale 1.6.
- AppImage zsync update path still never exercised end-to-end (an **RC exit criterion**).

## Issues and blockers

- **CI for the final HEAD is unverified — and the cause is your local `gh`, not CI.**
  All four workflows were green on `80352d3` (Docs, CI, Supply Chain incl. the
  no-egress attestation with its three negative controls, Distro). After that the
  Actions API began returning 503 for every call. It is **not** a GitHub outage:
  githubstatus reports Actions operational, `git` over SSH works fine (the pushes
  all landed), but `gh auth status` says:

      X Failed to log in to github.com account SimonKreitmayer (keyring)
        The token in keyring is invalid.

  Earlier `gh run list` calls in this same session succeeded, so the token was
  valid and was invalidated partway through (a locked keyring is the likely
  culprit). **Re-auth with `gh auth login` and check the runs for `b098727`.** The
  full local suite is green; the tree itself is not implicated.
- **Secret scanning + push protection could not be enabled** — the repo-settings API
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
   on the real Edge — W3/W2 are verified offscreen; the harness cannot instantiate
   `qrc:` widgets, so widget-instance survival is asserted via the Loader only.
2. **`gh auth login`**, then verify CI on `b098727` — the Actions API has been
   unreachable since mid-session because the local token went invalid, not because
   anything is wrong with the tree.
3. **Enable secret scanning + push protection** (Settings → Code security). Both
   are free on public repos and currently off; the API call to enable them was
   blocked by the permission classifier, correctly — it is yours to click.
4. **Make the four beta decisions** — they gate feature freeze.
5. Port the `animS/animL` pattern to `EdgeClone.qml`.
6. Decide the `--reset` backup policy.

### Install

```
sudo pacman -U /home/simon/IdeaProjects/XeneonEdge_Linux/packaging/local/xeneon-edge-hub-1.0.0.alpha.2.r83.g6885b80-1-x86_64.pkg.tar.zst
```

`sudo` is not passwordless here, so this is yours to run. It is a genuine **upgrade**
over the installed `1.0.0alpha.2-1` (`vercmp` = 1) — before this session it would
have been a downgrade. Restart the hub with **SIGTERM, never SIGKILL** (it saves
config on the way out), or just run `./scripts/update-local.sh`, which does the
build, the install and the graceful restart in one step.
