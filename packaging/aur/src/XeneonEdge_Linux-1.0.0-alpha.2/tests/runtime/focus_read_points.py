#!/usr/bin/env python3
"""Read the persisted Focus widget state from an isolated config.toml.

Usage: focus_read_points.py <config_dir>
Prints a one-line JSON: {"points":..,"doneToday":..,"running":..,"phase":..}
"""
import json
import os
import sys

try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib


def main() -> None:
    config_dir = sys.argv[1]
    with open(os.path.join(config_dir, "config.toml"), "rb") as f:
        data = tomllib.load(f)
    settings = json.loads(data["ui_state"])["settings"]["focus-1"]
    print(json.dumps({
        "points": settings.get("points"),
        "doneToday": settings.get("doneToday"),
        "running": settings.get("running"),
        "phase": settings.get("phase"),
    }))


if __name__ == "__main__":
    main()
