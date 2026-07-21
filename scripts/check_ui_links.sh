#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# check_ui_links.sh - a link the UI offers must actually go somewhere.
#
# The Manager's About pane shipped a "GitHub" button wired to
# `Qt.openUrlExternally("#")`. Clicking it did nothing at all: no browser, no
# error, no log line. That is worse than having no button - the user concludes
# the app is broken rather than the link, and there is no failure for anyone to
# notice. It survived every test and review because nothing could fail on it.
#
# So: every `Qt.openUrlExternally(...)` with a literal argument must name a real
# scheme. Non-literal arguments (a property, an expression) are skipped - this
# lint only judges what it can actually see.
#
# NOTE ON THE SCAN: this deliberately does NOT grep for `openUrlExternally("`.
# The first version did, and was born inert - the call it was written to catch
# is wrapped:
#
#     onClicked: Qt.openUrlExternally(
#         "https://github.com/...")
#
# so the `(` and the `"` are on different lines and the pattern never matched.
# The negative control caught it (the lint stayed green with the dead link put
# back), which is the entire argument for running one. Parse the CALL, not the
# LINE.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

python3 - "$@" <<'PYEOF'
import re, sys, pathlib

# openUrlExternally ( <whitespace/newlines> "literal" )
LITERAL = re.compile(r'openUrlExternally\s*\(\s*"([^"]*)"\s*\)', re.S)
# any call at all, so we can report how many we skipped as non-literal
ANY_CALL = re.compile(r'openUrlExternally\s*\(', re.S)
OK_SCHEMES = ("http://", "https://", "mailto:", "file://")

fail = 0
literals = skipped = 0
for root in ("ui/qml", "manager/qml"):
    for path in sorted(pathlib.Path(root).rglob("*.qml")):
        src = path.read_text(encoding="utf-8")
        calls = len(ANY_CALL.findall(src))
        found = LITERAL.findall(src)
        literals += len(found)
        skipped += calls - len(found)
        for url in found:
            if not url.startswith(OK_SCHEMES):
                # Report the line the literal sits on, not the call's start.
                line = src[:src.index('"%s"' % url)].count("\n") + 1
                print(f'  {path}:{line} - openUrlExternally("{url}") goes nowhere')
                fail = 1

if fail:
    print()
    print("FAIL: the UI offers a link that does nothing when clicked.")
    sys.exit(1)
print(f"OK: {literals} literal UI link(s) name a real scheme "
      f"({skipped} non-literal call(s) not judged).")
PYEOF
