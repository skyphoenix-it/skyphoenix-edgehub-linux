#!/usr/bin/env python3
"""Real synthetic-touch interaction tests: compact widget controls + page swipe.

Coordinates are for the fixed layout seeded in `run()` (Focus h1 top, Hydration
h1, Tasks h2) at the Edge's native 720x2560 — verified pixel-accurate.
"""
import os
from e2e_harness import doc, page, tile


def _seed_controls(h):
    h.set_state(doc([page("Ctl", [
        tile("focus-1", "focus", 1, 1),
        tile("hydration-1", "hydration", 1, 1),
        tile("tasks-1", "tasks", 1, 2),
    ])], settings={
        "focus-1": {"preset": "classic", "phase": "work", "running": False, "endEpoch": 0,
                    "pausedRemaining": 1500, "doneToday": 0, "day": h.today, "points": 0,
                    "dailyGoal": 4, "rewardPoints": True, "celebrate": True, "autoStartBreak": False},
        "hydration-1": {"count": 0, "goal": 8, "day": h.today},
        "tasks-1": {"items": [{"text": "Buy milk", "done": False},
                              {"text": "Ship the release", "done": False}]},
    }))


def run(h):
    # ── compact controls (touch) ──────────────────────────────────────────
    _seed_controls(h)
    st = h.settings()
    h.check("ctl_initial", st["focus-1"].get("running") is False and st["hydration-1"].get("count") == 0,
            "running=%s count=%s" % (st["focus-1"].get("running"), st["hydration-1"].get("count")))

    # Focus Start -> running true; tap again -> paused (running false)
    h.tap(317, 568)
    st = h.settings()
    h.check("focus_start_touch", st["focus-1"].get("running") is True, "running=%s" % st["focus-1"].get("running"))
    h.tap(317, 568)
    st = h.settings()
    h.check("focus_pause_touch", st["focus-1"].get("running") is False, "running=%s" % st["focus-1"].get("running"))

    # Hydration +1 x2 -> 2, then -1 -> 1
    h.tap(394, 955); h.tap(394, 955)
    st = h.settings()
    h.check("hydration_plus_touch", st["hydration-1"].get("count") == 2, "count=%s" % st["hydration-1"].get("count"))
    h.tap(321, 955)
    st = h.settings()
    h.check("hydration_minus_touch", st["hydration-1"].get("count") == 1, "count=%s" % st["hydration-1"].get("count"))

    # Task row toggle -> done true, tap again -> false
    h.tap(95, 1277)
    st = h.settings()
    h.check("task_toggle_on_touch", st["tasks-1"]["items"][0]["done"] is True,
            "done=%s" % st["tasks-1"]["items"][0]["done"])
    h.tap(95, 1277)
    st = h.settings()
    h.check("task_toggle_off_touch", st["tasks-1"]["items"][0]["done"] is False,
            "done=%s" % st["tasks-1"]["items"][0]["done"])

    # ── page swipe navigation (touch) ─────────────────────────────────────
    # Three visually-distinct pages of STATIC content on a STATIC backdrop, so
    # same-page grabs are pixel-stable (a live Clock/metrics widget or an
    # animated backdrop would make even a re-grab of the same page differ).
    static_bg = {"mode": "dark", "themeMode": "midnight", "accent": "#58A6FF",
                 "bgStyle": "none", "animatedBg": False, "glass": 0.55, "glow": False, "gridCols": 1}
    # Distinct full-screen STATIC wallpapers per page → adjacent pages differ
    # dramatically, a re-grab of the same page is stable.
    h.set_state(doc([
        {"name": "P1", "bg": {"wallpaper": "qrc:/wallpapers/midnight.png"}, "tiles": [tile("moon-1", "moon")]},
        {"name": "P2", "bg": {"wallpaper": "qrc:/wallpapers/sunset.png"}, "tiles": [tile("moon-2", "moon")]},
        {"name": "P3", "bg": {"wallpaper": "qrc:/wallpapers/teal.png"}, "tiles": [tile("moon-3", "moon")]},
    ], appearance=static_bg))
    grabs = []
    for i in range(3):
        p = os.path.join(h.work, "swipe_p%d.png" % i)
        h.check("swipe_grab_%d" % i, h.grab(p), p)
        grabs.append(p)
        if i < 2:
            h.swipe(600, 1280, 120, 1280)   # next page (right-to-left)

    def _avg(path):
        from PIL import Image
        return Image.open(path).convert("RGB").resize((1, 1)).getpixel((0, 0))

    def _dist(a, b):
        # Euclidean distance between the two grabs' AVERAGE colours — the distinct
        # per-page wallpaper dominates, so this cleanly separates "different page"
        # (large) from "same page" (~0), robust to hue and to grab timing.
        try:
            ca, cb = _avg(a), _avg(b)
            return sum((x - y) ** 2 for x, y in zip(ca, cb)) ** 0.5
        except Exception:
            return 999.0 if os.path.getsize(a) != os.path.getsize(b) else 0.0

    d01, d12 = _dist(grabs[0], grabs[1]), _dist(grabs[1], grabs[2])
    h.check("swipe_p0_p1_differ", d01 > 25, "pages 1->2 colour-distance %.0f" % d01)
    h.check("swipe_p1_p2_differ", d12 > 25, "pages 2->3 colour-distance %.0f" % d12)

    # swipe back to the first page
    h.swipe(120, 1280, 600, 1280); h.swipe(120, 1280, 600, 1280)
    back = os.path.join(h.work, "swipe_back.png")
    h.grab(back)
    db = _dist(grabs[0], back)
    h.check("swipe_back_to_p0", db < 12, "back-to-page-1 colour-distance %.0f (should be ~0)" % db)
