# Runtime end-to-end tests

These drive the **real hub binary** headless (offscreen QPA) and assert on the
state it *persists* to `config.toml` — complementing the QML unit harness
(`tests/ui/`), which exercises widget logic in isolation. They catch regressions
in the full load → run → save round-trip that a unit test cannot.

Every scenario: `0` pass, `1` fail, `77` skip (no hub binary). Hub binary
resolution: `$XENEON_HUB` → `./build/xeneon-edge-hub` → `xeneon-edge-hub` on
`PATH`. All are wired into `scripts/run_all_tests.sh` (suite 5).

```sh
bash tests/runtime/run_02_org_policy.sh              # any single scenario
XENEON_HUB=/usr/bin/xeneon-edge-hub bash tests/runtime/run_04_secret_refs.sh
```

## The battery

| # | script | asserts | ~cost |
|---|--------|---------|-------|
| — | `run_focus_goal_bonus.sh` | the Focus +50 daily-goal bonus fires exactly once, on the crossing session | 18 s |
| 01 | `run_01_wh_size_migration.sh` | an old `{w,h}`-vocabulary ui_state migrates to legal named `size`s per the DashboardStore table (exact values pinned), dead keys (`w`/`h`/`cols`/`gridCols`) are dropped, no tile or setting is lost, and a second launch round-trips the migrated doc unchanged | 16 s |
| 02 | `run_02_org_policy.sh` | via `XENEON_POLICY_PATH`: a forced preset replaces the session layout **without touching the user's config.toml** (byte-identical); a pinned `net_offline` blocks all egress while the user layout demonstrably runs; editing `appearance.netOffline` on disk between launches cannot lift the pin. A no-policy control run proves both observation channels first | 33 s |
| 03 | `run_03_update_check_off.sh` | on a default config the update check stays off: no enabled `updateCheck` key in a **hub-authored** save, no check activity in the log (proxy); runs `packaging/ci/no-egress.sh default` as the real zero-egress assertion when the box has `strace` + unprivileged userns, and prints which level ran | 10 s (+~15 s with no-egress) |
| 04 | `run_04_secret_refs.sh` | an `${env:VAR}` Bearer-token ref is resolved and *used* (the loopback sink sees `Authorization: Bearer <value>` — the non-vacuousness guard), yet after a real save round-trip the config carries only the REFERENCE and the resolved value appears nowhere under the config dir | 9 s |
| 05 | `run_05_corrupt_salvage.sh` | a torn-write config is preserved byte-for-byte under a timestamped `config.toml.corrupt-*.bak`, the canonical `config.toml.bak` is not clobbered, the hub stays up, `first_run_complete` survives (no wizard re-trigger), and the hub recovers to a valid persisted state | 8 s |

Shared plumbing: `rt_common.sh` (launching, liveness gate, loopback sink),
`seed_config.py` (ui_state JSON on stdin → nested config.toml),
`read_config.py` (config.toml → one JSON blob), `http_sink.py` (the loopback
egress observer: per-request JSON log incl. the Authorization header).

## Design rules (why the scenarios look like this)

- **Assert persisted/observable truth only.** A scenario's evidence is what the
  hub wrote to `config.toml`, what reached the loopback sink, or what its own
  log says — never internal state.
- **Every zero needs a non-zero control.** "No egress" / "no rewrite" is only
  meaningful next to a run of the *same seed* that produces egress/rewrites
  without the guarantee engaged (scenario 02 run 1, scenario 04's resolve
  guard, the liveness gate in all of them). This is what makes the scenarios
  falsifiable — each has been demonstrated to FAIL when its guarantee is
  deliberately broken.
- **The save trigger.** The hub only writes `config.toml` when something
  schedules a store save. The proven trigger is a Focus tile seeded RUNNING
  with an already-expired `endEpoch`: the 1 s tick fires a natural completion
  on load and the debounced save lands ~0.5–2 s later. Scenarios that assert
  "the hub re-serialized the doc" all use it, and check the `Configuration
  saved` log line so the assertion can never pass vacuously.
- **Known product gap (deliberately not asserted).** `salvage_partial_config()`
  in `core/src/config.rs` recovers `ui_state` only from a double-quoted TOML
  string, but the hub itself serializes it as a single-quoted *literal* — so
  after corruption the layout is re-seeded rather than salvaged (the user's
  layout survives only in the `.corrupt-*.bak`). Scenario 05 asserts the
  guarantees config.rs actually makes; fixing the quote handling would let it
  also assert layout survival.

## Gotchas (learned the hard way — see the script/helper comments)

- **Config is nested TOML.** `[display]`/`[theme]`/`[startup]`/`[widgets]` are
  required tables. A flat layout deserialize-fails; the Rust `toml` crate reports
  it as *"parse error at line 1, column 1"* (a serde error with no span) and the
  core then **salvages into the default layout**, silently dropping the seed.
- **`ui_state` must be a single-quoted TOML literal string.** The embedded JSON
  has double quotes; a basic `"..."` string with `\"`-escapes is rejected. This
  is also exactly how the hub itself writes it (verified against a real save).
- **Kill with SIGKILL, not SIGTERM — but only after the save landed.** The
  hub's graceful-shutdown handler can hang on sensor/socket teardown, so runs
  are bounded with `timeout --foreground -s KILL`. That is safe **because** no
  scenario depends on shutdown-time saving: the debounced store save has
  already written `config.toml` seconds before the kill. Never SIGKILL a hub
  whose *expected save has not had time to land* — rc `137` doubles as the
  liveness gate ("alive for the whole window").
  (`--foreground` keeps the kill off the invoking shell's process group;
  without it every run prints a spurious "Killed" job notice.)
- **Never `pkill -f xeneon-edge-hub`** in a script that also names the binary —
  `pkill -f` matches the script's own command line (and any real hub the user has
  open). `timeout` reaps each isolated run; no manual cleanup is needed.
- Each run gets its own `XDG_RUNTIME_DIR` so the single-instance **lock** never
  collides with another run or a live instance. `QLockFile` honours
  `XDG_RUNTIME_DIR`, so that isolation is real.
- **The control socket IS isolated by `XDG_RUNTIME_DIR`.** Both ends resolve it
  through `app/src/control_socket_path.h` to
  `$XDG_RUNTIME_DIR/xeneon-edge-hub-ctl`, so each run's socket is as private as
  its lock. This was NOT always true, and the failure was nasty: the socket used
  to be a bare name, which Qt resolves via `QDir::tempPath()` — so every hub
  launched here bound the REAL `/tmp/xeneon-edge-hub-ctl` and
  `ControlServer::start()`'s `removeServer()` unlinked it, silently stranding a
  live hub's Manager connection (the hub keeps its listening fd, so it looks
  healthy) until it restarted. Keep the isolation: give each run its own
  `XDG_RUNTIME_DIR`, and note that a path over ~107 bytes won't fit
  `sockaddr_un` — keep run dirs short (`mktemp -d /tmp/...`, never a deep
  workdir).
- A `timeout -s KILL`'d run leaves a stale socket file in its own run dir
  (harmless — it dies with the dir, and the next hub's `removeServer()` clears
  any leftover of its own).
- **QML `console.log` is invisible in product logs** (the hub initializes Rust
  tracing at `info`; Qt debug-level messages are filtered). Scenario assertions
  must not depend on QML debug output — assert on the persisted doc, the sink,
  or `INFO`-level lines (`Configuration saved`, `Org policy loaded and
  applied`, `ControlServer listening`).
