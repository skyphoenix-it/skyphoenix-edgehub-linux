#!/usr/bin/env python3
"""Seed an isolated hub config.toml from a ui_state JSON document on stdin.

Usage: seed_config.py <config_dir> [--first-run-complete true|false]

Generalisation of focus_seed_config.py for the scenario battery: the caller
builds the ui_state document (layout + per-widget settings + appearance) and
pipes it in as JSON; this writes the full NESTED config.toml around it.

Schema details the hub's Rust core (`toml` crate + serde) is strict about -
learned the hard way (see tests/runtime/README.md):

  * The config is NESTED: [display] / [theme] / [startup] / [widgets] are
    required tables. A flat key layout deserialize-fails ("TOML parse error at
    line 1, column 1") and the core salvages into the default starter layout,
    silently discarding the seed.
  * `ui_state` must be a single-quoted TOML *literal* string - exactly how the
    hub itself serializes it. JSON never contains a single quote, so a literal
    needs no escaping (asserted below).
"""
import json
import sys


def build_config(ui_state: str, first_run_complete: bool) -> str:
    assert "'" not in ui_state, "ui_state must not contain a single quote"
    return "\n".join([
        "schema_version = 1",
        "first_run_complete = %s" % ("true" if first_run_complete else "false"),
        "ui_state = '%s'" % ui_state,
        "",
        "[display]",
        'fallback_behavior = "hide"',
        'starter_layout = "productivity"',
        "",
        "[theme]",
        'mode = "dark"',
        'accent_color = "#58A6FF"',
        "reduced_motion = false",
        "",
        "[startup]",
        "autostart = false",
        "reconnect_on_hotplug = true",
        "notify_on_disconnect = false",
        "",
        "[widgets]",
        "version = 1",
        "instances = []",
        "",
    ])


def main() -> None:
    config_dir = sys.argv[1]
    first_run = True
    if "--first-run-complete" in sys.argv:
        first_run = sys.argv[sys.argv.index("--first-run-complete") + 1] == "true"
    doc = json.load(sys.stdin)                      # validate it IS json
    ui_state = json.dumps(doc, separators=(",", ":"))
    import os
    os.makedirs(config_dir, exist_ok=True)
    with open(os.path.join(config_dir, "config.toml"), "w") as f:
        f.write(build_config(ui_state, first_run))
    print("seeded %s/config.toml (%d tiles)" % (
        config_dir, sum(len(p.get("tiles", [])) for p in doc.get("pages", []))))


if __name__ == "__main__":
    main()
