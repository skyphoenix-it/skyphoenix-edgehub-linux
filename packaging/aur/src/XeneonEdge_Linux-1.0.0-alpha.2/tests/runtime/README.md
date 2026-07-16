# Runtime end-to-end tests

These drive the **real hub binary** headless (offscreen QPA) and assert on the
state it *persists* to `config.toml` — complementing the QML unit harness
(`tests/ui/`), which exercises widget logic in isolation. They catch regressions
in the full load → run → save round-trip that a unit test cannot.

## `run_focus_goal_bonus.sh`

Verifies the Focus widget's daily-goal bonus fires **exactly once** — on the
session that crosses the goal (`done === dailyGoal`), never again for sessions
past it. Each scenario seeds an isolated config with a Focus tile one step from
the goal, running with an already-expired timer, so the hub's 1 s tick fires a
natural completion on load; the script then reads back the persisted points.

```sh
bash tests/runtime/run_focus_goal_bonus.sh        # uses ./build or installed hub
XENEON_HUB=/usr/bin/xeneon-edge-hub bash tests/runtime/run_focus_goal_bonus.sh
```

Exit: `0` pass, `1` fail, `77` skip (no hub binary found). Hub binary resolution:
`$XENEON_HUB` → `./build/xeneon-edge-hub` → `xeneon-edge-hub` on `PATH`.

## Gotchas (learned the hard way — see the script/helper comments)

- **Config is nested TOML.** `[display]`/`[theme]`/`[startup]`/`[widgets]` are
  required tables. A flat layout deserialize-fails; the Rust `toml` crate reports
  it as *"parse error at line 1, column 1"* (a serde error with no span) and the
  core then **salvages into the default layout**, silently dropping the seed.
- **`ui_state` must be a single-quoted TOML literal string.** The embedded JSON
  has double quotes; a basic `"..."` string with `\"`-escapes is rejected.
- **Kill with SIGKILL, not SIGTERM.** The hub's graceful-shutdown handler can
  hang on sensor/socket teardown. The debounced store save has already written
  `config.toml` long before the timeout, so `timeout -s KILL` is safe.
- **Never `pkill -f xeneon-edge-hub`** in a script that also names the binary —
  `pkill -f` matches the script's own command line (and any real hub the user has
  open). `timeout -s KILL` reaps each isolated run; no manual cleanup is needed.
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
  `sockaddr_un` — keep run dirs short.
- A `timeout -s KILL`'d run leaves a stale socket file in its own run dir
  (harmless — it dies with the dir, and the next hub's `removeServer()` clears
  any leftover of its own).
