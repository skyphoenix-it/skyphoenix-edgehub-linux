#!/usr/bin/env python3
"""E2E widget-lifecycle suite for the Xeneon Edge hub.

For every one of the 22 widget types this exercises ADD -> RENDER -> RESIZE ->
REMOVE over the control-socket IPC (set_state / get_state), grabs a screenshot
of each rendered widget, and scans the hub log for fallback / unknown-type
errors. Every step is guarded so a single failure records a FAIL via h.check()
and never aborts the run.

The runner owns launch/stop; this module only calls run(h) and assumes the hub
is already up and h.get_state() works. Per-widget settings are keyed by tile id
(store.settingsFor(id)), matching the hub's DashboardStore contract.
"""
import os
from e2e_harness import doc, page, tile

# The 22 widget types the dashboard ships.
WIDGETS = [
    "cpu", "gpu", "ram", "net", "disk", "sensors", "clock", "analog", "moon",
    "focus", "tasks", "rightnow", "notes", "habit", "hydration", "break",
    "media", "calendar", "weather", "countdown", "eod", "quote",
]


def _seed(wtype, tid, today):
    """Sensible per-instance settings (keyed by tile id) for widgets that
    need data to render meaningfully. Empty for widgets that self-seed."""
    if wtype == "weather":
        return {tid: {"lat": 52.52, "lon": 13.405, "place": "Berlin"}}
    if wtype == "tasks":
        return {tid: {"items": [{"text": "A", "done": False}]}}
    if wtype in ("hydration", "focus", "habit"):
        return {tid: {"day": today}}
    return {}


def _log_tail(h, n=8000):
    """Last n chars of the hub log (recent output only, so we don't trip over
    unrelated startup noise from before this widget was added)."""
    try:
        with open(os.path.join(h.work, "hub.log"), "r", errors="replace") as f:
            return f.read()[-n:]
    except Exception:
        return ""


def run(h):
    for wtype in WIDGETS:
        tid = wtype + "-1"
        seed = _seed(wtype, tid, h.today)

        # ── ADD ──────────────────────────────────────────────────────────
        try:
            d = doc([page("P1", [tile(tid, wtype)])], settings=seed)
            h.set_state(d)
            st = h.get_state()
            tiles = st.get("pages", [{}])[0].get("tiles", [])
            ids = [t.get("id") for t in tiles]
            present = tid in ids
            h.check("add_" + wtype, present, "tiles=%r" % ids)
        except Exception as e:
            h.check("add_" + wtype, False, "exc: %r" % e)
            # Can't meaningfully continue this widget's lifecycle.
            continue

        # ── RENDER (screenshot) ──────────────────────────────────────────
        try:
            path = os.path.join(h.work, "widget_%s.png" % wtype)
            ok = h.grab(path)
            h.check("render_" + wtype, ok, path)
        except Exception as e:
            h.check("render_" + wtype, False, "exc: %r" % e)

        # ── no fallback / unknown-type error in the log ──────────────────
        try:
            tail = _log_tail(h)
            no_err = ("is not a type" not in tail) and ("Unavailable" not in tail)
            h.check("no_error_" + wtype, no_err,
                    "log clean" if no_err else "fallback/unknown-type logged")
        except Exception as e:
            h.check("no_error_" + wtype, False, "exc: %r" % e)

        # ── RESIZE to 2x2 (some widgets clamp width; require h==2) ────────
        try:
            d2 = doc([page("P1", [tile(tid, wtype, w=2, h=2)])], settings=seed)
            h.set_state(d2)
            st = h.get_state()
            t0 = st.get("pages", [{}])[0].get("tiles", [{}])[0]
            w, hh = t0.get("w"), t0.get("h")
            if w == 2 and hh == 2:
                h.check("resize_" + wtype, True, "w=2 h=2")
            else:
                # Width clamp is acceptable; height must have grown to 2.
                h.check("resize_" + wtype, hh == 2,
                        "clamped w=%r h=%r" % (w, hh))
        except Exception as e:
            h.check("resize_" + wtype, False, "exc: %r" % e)

        # ── REMOVE (empty page) ──────────────────────────────────────────
        try:
            d3 = doc([page("P1", [])], settings={})
            h.set_state(d3)
            st = h.get_state()
            tiles = st.get("pages", [{}])[0].get("tiles", [])
            h.check("remove_" + wtype, len(tiles) == 0, "tiles=%d" % len(tiles))
        except Exception as e:
            h.check("remove_" + wtype, False, "exc: %r" % e)
