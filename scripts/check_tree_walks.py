#!/usr/bin/env python3
"""Static guard against unmemoised multi-axis QML scene-graph walks.

WHY THIS EXISTS
---------------
On 2026-07-19 a recursive scene-graph walk drove qmltestrunner to 18.8 GB RSS.
The kernel fired a SYSTEM-WIDE OOM and killed the developer's IDE. Three
independent copies of the same bug were found in this repo:

    tests/gui/GuiUtil.js        children + data              -> 18.8 GB
    tests/ui/tst_manager.qml    children + data              -> 20 GB in 25 s
    tests/ui/tst_gen_notes.qml  children + contentItem       -> exponential

THE BUG
-------
A QML node is reachable through more than one "child axis":
`children`, `data`, `contentItem`, `contentData`, `visibleChildren`, `resources`.
These OVERLAP - `data` is a superset of `children`, and a Control's
`contentItem` is itself one of its `children`. A recursive walk that descends
two or more of these axes without remembering what it has already visited
re-walks each node's subtree once per distinct path. That is exponential in
depth, not quadratic: 1,701 real nodes produced >2,000,000 visits.

Descending exactly ONE axis is a true tree walk and is always safe.

WHAT THIS CHECKS
----------------
Every recursive function in the repo's .qml/.js files. If a function recurses
into two or more distinct child axes AND has no visited-set guard, it fails.

Recognised guards: a `Set`/`WeakSet` with .has()/.add(), or an array with
.indexOf()/.includes() used as a seen-list.

Run:  python3 scripts/check_tree_walks.py [--verbose]
Exit: 0 = clean, 1 = an unguarded multi-axis walker exists.
"""
from __future__ import annotations

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Directories that hold build output or vendored copies, never source of truth.
SKIP_DIRS = {
    "build", "cmake-build-release", "build-appimage", "build-qa", "dist",
    ".git", "node_modules", ".flatpak-builder", "target", "gui-evidence",
}

# The overlapping child axes. `children` alone is a tree; two or more overlap.
AXES = ("children", "data", "contentItem", "contentData", "visibleChildren", "resources")

# A visited-set guard, in any of the idioms used in this repo.
GUARD_RE = re.compile(
    r"""(
        new\s+(Weak)?Set\s*\(              |   # new Set()
        \.has\s*\(                         |   # seen.has(n)
        \.add\s*\(                         |   # seen.add(n)
        \.indexOf\s*\([^)]*\)\s*[<>]=?\s*0 |   # seen.indexOf(n) >= 0
        \.includes\s*\(                    |   # seen.includes(n)
        # A hand-rolled linear seen-scan, as in tst_gen_rightnow.qml:
        #   for (var s = 0; s < seen.length; s++) if (seen[s] === node) return
        #   seen.push(node)
        \b(seen|visited|memo)\b[\s\S]{0,200}?\.push\s*\(
    )""",
    re.VERBOSE,
)

FUNC_RE = re.compile(r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(")


def iter_source_files(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if fn.endswith((".qml", ".js")):
                yield os.path.join(dirpath, fn)


def extract_function_bodies(text: str):
    """Yield (name, start_line, body) for each `function name(...) { ... }`.

    Brace-matching is adequate here: QML/JS in this repo does not put unbalanced
    braces inside strings in walker functions. Regex-only would not survive
    nested closures, which every one of these walkers has.
    """
    for m in FUNC_RE.finditer(text):
        name = m.group(1)
        brace = text.find("{", m.end())
        if brace == -1:
            continue
        depth, i, n = 0, brace, len(text)
        while i < n:
            c = text[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = text[brace : i + 1]
        yield name, text.count("\n", 0, m.start()) + 1, body


def axes_used(body: str) -> set[str]:
    used = set()
    for axis in AXES:
        # `node.children`, `n.data`, `x.contentItem` - a property access.
        if re.search(r"\.\s*" + axis + r"\b", body):
            used.add(axis)
    return used


def analyse(path: str):
    """Return a list of (name, line, axes) for unguarded multi-axis walkers."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError):
        return []

    findings = []
    for name, line, body in extract_function_bodies(text):
        # Only recursive walkers matter. Direct self-call, or delegation to a
        # helper that is itself recursive (the `walk -> _walkSeen` pattern).
        recursive = re.search(r"\b" + re.escape(name) + r"\s*\(", body[1:])
        if not recursive:
            continue
        used = axes_used(body)
        if len(used) < 2:
            continue  # single axis = true tree = safe
        if GUARD_RE.search(body):
            continue  # has a visited-set
        findings.append((name, line, sorted(used)))
    return findings


def main() -> int:
    verbose = "--verbose" in sys.argv
    total_funcs = 0
    scanned = 0
    failures = []

    for path in sorted(iter_source_files(REPO)):
        scanned += 1
        rel = os.path.relpath(path, REPO)
        for name, line, used in analyse(path):
            failures.append((rel, name, line, used))
        if verbose:
            with open(path, encoding="utf-8", errors="ignore") as fh:
                total_funcs += len(list(extract_function_bodies(fh.read())))

    print(f"check_tree_walks: scanned {scanned} .qml/.js files")
    if verbose:
        print(f"                  {total_funcs} functions parsed")

    if not failures:
        print("OK: no unmemoised multi-axis scene-graph walkers")
        return 0

    print()
    print("FAIL: unmemoised multi-axis scene-graph walker(s) found.")
    print("These re-walk each subtree once per path - exponential in depth.")
    print("Add a visited-set (see scripts/lib/run_bounded.sh header and")
    print("tests/gui/GuiUtil.js:_walk for the canonical fix).")
    print()
    for rel, name, line, used in failures:
        print(f"  {rel}:{line}  function {name}()  descends: {', '.join(used)}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
