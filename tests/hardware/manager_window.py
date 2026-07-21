#!/usr/bin/env python3
"""manager_window.py - proof that the Manager is the window we are clicking.

WHY THIS EXISTS (2026-07-20)
────────────────────────────────────────────────────────────────────────────
Every Manager test clamps its synthetic events to the Manager's window RECT.
That confines the cursor, and it is necessary - but it does NOT establish that
the Manager is the window RECEIVING events in that rect. Nothing did.

The first ever run of manager_gui_test.py proved the gap the expensive way: the
owner's browser raised itself over the Manager on DP-2 mid-run, so five sidebar
clicks went into a documentation page. The run reported four Manager defects
("the click did not change tabs", "SELECTED row is None") that did not exist,
and six real clicks landed in an unrelated application.

`assert_rect_on_a_desktop_screen()` cannot catch this. It only asserts the rect
lies on a real non-Edge screen - a correct window, an occluded one and a stale
rect all satisfy it identically.

THE SIGNAL
────────────────────────────────────────────────────────────────────────────
The Manager always has exactly ONE sidebar row filled with the accent. So:

    exactly one accent row  -> we are looking at the Manager (and we know which
                               tab is selected)
    no accent row at all    -> we are NOT looking at the Manager

That distinction is the whole thing. It was already computable before this
module existed, and was misread as "the wrong tab is selected" - which turned an
environment problem into four fabricated bug reports. Occlusion is not a product
failure and must never be reported as one.

USE
────────────────────────────────────────────────────────────────────────────
    import manager_window as mw
    p = mw.guard_pointer(u.VPointer(cw, ch, rect_xywh, guard=g), rect, work)
    p.tap(x, y)        # refuses (returns False) if the Manager is not in front

`guard_pointer` is a drop-in wrapper: it forwards every attribute to the real
pointer and only interposes on the emitting calls.
"""
import os

import desktop_target as dt

# Sidebar row centres in logical pixels. The sidebar is anchored at the top and
# its rows have fixed QML heights, so these coordinates do not move when only
# the window height changes. The old height fractions turned Screens at y=164
# into y=126 in a 1000px-tall Manager and falsely reported the selected Look row.
ROW_Y = {"Screens": 164, "Look": 220, "Images": 276,
         "Device": 332, "About": 388}
ROW_X = 120


def active_row(path, win_w=None, win_h=None):
    """Which sidebar row is selected, read from the accent fill - or None.

    None means NO row is accented, i.e. this is not the Manager. Callers must
    treat that as "lost the window", never as "wrong tab".

    The selected row is the accent (~rgb(237,109,31)); the others are the cream
    page background (~rgb(255,253,250)).
    """
    from PIL import Image
    im = Image.open(path).convert("RGB")
    hits = []
    for name, y in ROW_Y.items():
        x = ROW_X
        if 0 <= x < im.size[0] and 0 <= y < im.size[1]:
            r, g, b = im.getpixel((x, y))
            if r > 180 and g < 160 and b < 130:
                hits.append(name)
    return hits[0] if len(hits) == 1 else (hits or None)


def grab_rect(rect, work, tag="frontcheck"):
    """Grab the screen and crop to the Manager's rect. Returns a path or None."""
    name, x, y, w, h = rect
    full = dt._full_grab(work, tag)
    if not full:
        return None
    try:
        from PIL import Image
        out = os.path.join(work, "_%s.png" % tag)
        Image.open(full).crop((x, y, x + w, y + h)).save(out)
        os.unlink(full)
        return out
    except Exception:
        return None


def is_in_front(rect, work):
    """True if the Manager is the window rendering in its own rect."""
    p = grab_rect(rect, work)
    if not p:
        return False
    ok = active_row(p) is not None
    try:
        os.unlink(p)
    except OSError:
        pass
    return ok


class GuardedPointer:
    """Wraps a VPointer and refuses to emit unless the Manager is in front.

    Checked BEFORE each emitting call, not after: a post-hoc check catches the
    occlusion one click too late, and that one click is exactly the one that
    lands in someone else's window.
    """

    _EMITTERS = ("tap", "press", "move", "release", "click", "drag")

    def __init__(self, pointer, rect, work):
        self._p, self._rect, self._work = pointer, rect, work
        self.refused = 0

    def __getattr__(self, name):
        attr = getattr(self._p, name)
        if name not in self._EMITTERS or not callable(attr):
            return attr

        def guarded(*a, **kw):
            if not is_in_front(self._rect, self._work):
                self.refused += 1
                print("  REFUSED %s%r: the Manager is not the window in its own "
                      "rect (occluded?). Emitting nothing." % (name, a), flush=True)
                return False
            return attr(*a, **kw)
        return guarded


def guard_pointer(pointer, rect, work):
    return GuardedPointer(pointer, rect, work)
