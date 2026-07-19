#!/usr/bin/env python3
"""desktop_target.py — confine synthetic input to a DESKTOP application window.

The Edge harness (`uinput_touch.py`) clamps every event to the Edge rect and
offers no unclamped API, which is exactly why it is safe. But the Manager
deliberately places itself OFF the Edge (`manager/src/main.cpp:85`,
`placeManagerOffEdge`), so that guarantee also makes the Manager untestable with
real input.

This module relaxes the confinement in the narrowest way that still keeps a hard
guarantee: instead of "events cannot leave the Edge", the rule becomes **"events
cannot leave the window under test"**. `VPointer` already accepts an arbitrary
rect, so no new emit path and no new clamp logic is introduced — only a
different, verified rect.

Owner approval (2026-07-19): "I approve that my cursor moves around, as long as
the clicks and so on are focused on the applications that are actually being
tested." That sentence is the contract this module implements:

  1. SEPARATE GATE. `XENEON_HW_INPUT_DESKTOP=1`, distinct from the Edge gate.
     Setting the Edge gate alone must never move the cursor off the Edge.
  2. RECT IS A SCREEN THE TARGET OWNS, never the whole canvas. The clamp
     therefore cannot reach another monitor, the panel, or the desktop at large.
  3. RENDER-VERIFIED BEFORE THE FIRST EVENT. The target rect must visibly change
     when we change the app's state. No verification -> no injection, loud raise.
     Without this a mispositioned window means clicking someone's editor.
  4. The Edge is EXCLUDED as a candidate: this path is for desktop windows, and
     anything targeting the panel must use the Edge-confined injector instead.

The user-activity kill switch (`input_guard.py`) applies unchanged: real input
from the owner aborts injection for the rest of the run.
"""
import os
import re
import subprocess
import time

import uinput_touch as u

DESKTOP_GATE_ENV = "XENEON_HW_INPUT_DESKTOP"


class DesktopGateError(RuntimeError):
    pass


class TargetNotVerified(RuntimeError):
    pass


def require_desktop_gate():
    """Raise unless the owner explicitly opted into desktop-wide injection."""
    if os.environ.get(DESKTOP_GATE_ENV) != "1":
        raise DesktopGateError(
            "desktop injection is OFF. It moves the real cursor on the real "
            "desktop, so it needs its own opt-in: %s=1. The Edge gate (%s) "
            "deliberately does NOT enable it."
            % (DESKTOP_GATE_ENV, u.GATE_ENV))


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def screens():
    """[(name, x, y, w, h)] from kscreen-doctor, enabled outputs only.

    kscreen-doctor colourises its output, so the raw text is full of ANSI SGR
    escapes ("\x1b[01;32mOutput: \x1b[0;0m1 DP-3 ..."). Parsing without
    stripping them silently yields an EMPTY screen list, which downstream reads
    as "no candidate screens" rather than as a parse failure.
    """
    out = subprocess.run(["kscreen-doctor", "-o"], capture_output=True, text=True).stdout
    out = ANSI_RE.sub("", out)
    found, name = [], None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("Output:"):
            parts = s.split()
            name = parts[2] if len(parts) > 2 else None
        elif s.startswith("Geometry:") and name:
            try:
                pos, size = s.split(None, 1)[1].split()
                x, y = (int(v) for v in pos.split(","))
                w, h = (int(v) for v in size.split("x"))
                found.append((name, x, y, w, h))
            except ValueError:
                pass
            name = None
    return found


def canvas_size(scr=None):
    scr = scr or screens()
    return (max(x + w for _, x, y, w, h in scr),
            max(y + h for _, x, y, w, h in scr))


def desktop_screens(edge_name):
    """Every enabled screen EXCEPT the Edge. Candidates for a desktop window."""
    return [s for s in screens() if s[0] != edge_name]


def _avg(path, rect):
    from PIL import Image
    x, y, w, h = rect
    return Image.open(path).convert("RGB").crop((x, y, x + w, y + h)).resize((1, 1)).getpixel((0, 0))


def _full_grab(tmpdir, tag):
    p = os.path.join(tmpdir, "_dt_%s.png" % tag)
    try:
        os.unlink(p)
    except OSError:
        pass
    # Same staleness rule as e2e_harness.grab: spectacle is single-instance and
    # returns rc=0 whether or not it captured, so wait for the FILE.
    for attempt in (1, 2):
        subprocess.run(["spectacle", "-b", "-n", "-f", "-o", p],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(30):
            if os.path.exists(p) and os.path.getsize(p) > 0:
                return p
            time.sleep(0.1)
        if attempt == 1:
            time.sleep(1.0)
    return None


def locate_and_verify(tmpdir, edge_name, mutate_a, mutate_b, min_dist=25):
    """Find which desktop screen the target occupies, and PROVE it.

    mutate_a/mutate_b put the app into two visually different states. The screen
    whose rect changes most between the two grabs is the target. If no screen
    changes by more than `min_dist`, we do not know where the window is and
    injection must not happen — same rule as the Edge probe.

    Returns (name, x, y, w, h).
    """
    cands = desktop_screens(edge_name)
    if not cands:
        raise TargetNotVerified("no non-Edge screen to search")

    mutate_a()
    time.sleep(1.0)
    pa = _full_grab(tmpdir, "a")
    mutate_b()
    time.sleep(1.0)
    pb = _full_grab(tmpdir, "b")
    if not pa or not pb:
        raise TargetNotVerified("could not grab the desktop for verification")

    best, best_dist = None, -1.0
    for (name, x, y, w, h) in cands:
        a, b = _avg(pa, (x, y, w, h)), _avg(pb, (x, y, w, h))
        d = sum((p - q) ** 2 for p, q in zip(a, b)) ** 0.5
        print("    candidate %-8s %dx%d+%d+%d  delta=%.0f" % (name, w, h, x, y, d))
        if d > best_dist:
            best, best_dist = (name, x, y, w, h), d
    if best_dist < min_dist:
        raise TargetNotVerified(
            "no desktop screen changed between the two app states (best delta "
            "%.0f < %d). The window is not where we think it is — refusing to "
            "inject." % (best_dist, min_dist))
    print("    TARGET VERIFIED: %s delta=%.0f" % (best[0], best_dist))
    return best


def pointer_for(rect, guard=None):
    """A VPointer clamped to `rect`. Requires the desktop gate."""
    require_desktop_gate()
    cw, ch = canvas_size()
    _, x, y, w, h = rect if len(rect) == 5 else (None,) + tuple(rect)
    return u.VPointer(cw, ch, (x, y, w, h), guard=guard)


MGR_PLACE_RE = re.compile(
    r'Placing Manager on "([^"]+)" at (-?\d+) , (-?\d+) (\d+) x (\d+)')


def manager_rect_from_log(log_path, timeout=15.0):
    """The Manager's REAL window rect, parsed from its own placement log line.

    This is what makes the clamp window-precise instead of monitor-precise. The
    Manager has no control socket, and KWin exposes no window geometry over DBus
    without loading a script, so the app logging its own final rect
    (manager/src/main.cpp, placeManagerOffEdge) is the only machine-readable
    source. Clamping to the monitor would satisfy "cannot leave this screen" but
    NOT the owner's actual constraint, which is "clicks focused on the
    application being tested" — on a 5120x1440 monitor those are very different.

    Returns (name, x, y, w, h) or None if the line never appears.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(log_path, "r", errors="replace") as fh:
                m = None
                for line in fh:
                    hit = MGR_PLACE_RE.search(line)
                    if hit:
                        m = hit               # last one wins (re-placement)
                if m:
                    return (m.group(1), int(m.group(2)), int(m.group(3)),
                            int(m.group(4)), int(m.group(5)))
        except OSError:
            pass
        time.sleep(0.25)
    return None


def assert_rect_on_a_desktop_screen(rect, edge_name):
    """The window rect must lie on a NON-Edge screen, and inside it.

    Belt-and-braces against a stale or bogus log line: if the parsed rect does
    not sit within a real desktop screen, we do not know where the window is and
    must not inject. Same refuse-by-default rule as the Edge probe.
    """
    _, x, y, w, h = rect
    for (name, sx, sy, sw, sh) in desktop_screens(edge_name):
        if sx <= x and sy <= y and x + w <= sx + sw and y + h <= sy + sh:
            return name
    raise TargetNotVerified(
        "Manager rect %r is not contained in any non-Edge screen — refusing to "
        "inject." % (rect,))
