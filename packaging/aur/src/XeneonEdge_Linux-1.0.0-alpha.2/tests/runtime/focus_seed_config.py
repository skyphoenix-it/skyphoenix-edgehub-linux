#!/usr/bin/env python3
"""Seed an isolated hub config.toml with a single Focus widget.

Usage: focus_seed_config.py <config_dir> <doneToday> <dailyGoal>

Writes <config_dir>/config.toml. The Focus instance is seeded RUNNING with an
already-expired endEpoch, so the hub's 1 s tick fires a *natural* completion
(advance(true)) immediately on load — driving one real session end.

Two schema details the hub's Rust core (`toml` crate + serde) is strict about,
learned the hard way:

  * The config is NESTED: [display] / [theme] / [startup] / [widgets] are
    required tables. A flat key layout deserializes-fails and the core reports
    it as "TOML parse error at line 1, column 1" (a serde error with no span),
    then salvages into the default starter layout — silently discarding the seed.
  * `ui_state` must be a single-quoted TOML *literal* string. The embedded JSON
    contains double quotes; a basic "..."-string with \\"-escapes is rejected.
    JSON never contains a single quote, so a literal string needs no escaping.
"""
import json
import os
import sys
import datetime

PAST_EPOCH_MS = 1_600_000_000_000  # 2020 → remaining clamps to 0 at once


def build_config(done_today: int, daily_goal: int, today: str) -> str:
    ui_state = json.dumps({
        "version": 1,
        "appearance": {"mode": "dark", "accent": "#58A6FF"},
        "settings": {"focus-1": {
            "preset": "classic", "phase": "work", "running": True,
            "endEpoch": PAST_EPOCH_MS, "pausedRemaining": 1500,
            "doneToday": done_today, "day": today, "points": 0,
            "dailyGoal": daily_goal, "rewardPoints": True, "celebrate": True,
            "autoStartBreak": False,
        }},
        "pages": [{"name": "Focus", "tiles": [
            {"id": "focus-1", "type": "focus", "w": 1, "h": 2}
        ]}],
    })
    assert "'" not in ui_state, "JSON unexpectedly contains a single quote"
    return "\n".join([
        "schema_version = 1",
        "first_run_complete = true",
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
    config_dir, done_today, daily_goal = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    today = datetime.date.today().strftime("%Y-%m-%d")
    os.makedirs(config_dir, exist_ok=True)
    with open(os.path.join(config_dir, "config.toml"), "w") as f:
        f.write(build_config(done_today, daily_goal, today))
    print(f"seeded doneToday={done_today} dailyGoal={daily_goal} day={today}")


if __name__ == "__main__":
    main()
