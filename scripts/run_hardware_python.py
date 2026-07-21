#!/usr/bin/env python3
"""Run one hardware-suite module against explicitly selected binaries.

The hardware harness predates the strict release build and intentionally keeps
its developer defaults at ``build/xeneon-edge-{hub,manager}``.  Release scripts
must not rewrite or shadow that mutable directory, so this small bootstrap loads
the shared harness first, replaces those two process paths from the environment,
and only then executes the requested suite.  Ordinary runs without overrides
therefore retain exactly the historical paths.
"""

import os
import runpy
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: run_hardware_python.py TEST.py [args ...]", file=sys.stderr)
        return 2

    target = os.path.abspath(sys.argv[1])
    if not os.path.isfile(target):
        print("hardware test not found: %s" % target, file=sys.stderr)
        return 2

    hardware_dir = os.path.dirname(target)
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    sys.path.insert(0, hardware_dir)

    import e2e_harness  # pylint: disable=import-outside-toplevel

    hub = os.environ.get(
        "XENEON_HUB", os.path.join(repo, "build", "xeneon-edge-hub")
    )
    manager = os.environ.get(
        "XENEON_MANAGER", os.path.join(repo, "build", "xeneon-edge-manager")
    )
    e2e_harness.HUB = os.path.abspath(hub)
    e2e_harness.MANAGER = os.path.abspath(manager)

    # The function's default tuple was bound when e2e_harness was imported.
    # Replace that tuple as well as the module globals so a suite's zero-argument
    # freshness check and its later process launches inspect the same binaries.
    e2e_harness.assert_binaries_current.__defaults__ = (
        (e2e_harness.HUB, e2e_harness.MANAGER),
    )

    sys.argv = [target, *sys.argv[2:]]
    runpy.run_path(target, run_name="__main__")
    return 0


if __name__ == "__main__":
    sys.exit(main())
