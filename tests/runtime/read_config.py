#!/usr/bin/env python3
"""Dump the persisted hub config as one JSON object for shell assertions.

Usage: read_config.py <config_dir>

Prints: {"first_run_complete": bool,
         "ui_state": <parsed object or null>,     # null = absent/unparsable
         "raw_ui_state": "<verbatim string or null>"}
"""
import json
import os
import sys

try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib


def main() -> None:
    with open(os.path.join(sys.argv[1], "config.toml"), "rb") as f:
        data = tomllib.load(f)
    raw = data.get("ui_state")
    parsed = None
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
        except ValueError:
            parsed = None
    print(json.dumps({
        "first_run_complete": bool(data.get("first_run_complete", False)),
        "ui_state": parsed,
        "raw_ui_state": raw,
    }))


if __name__ == "__main__":
    main()
