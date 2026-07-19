#!/usr/bin/env python3
"""e2e_buildup.py — incremental build-up scenario on the REAL Edge panel.

Owner-requested (2026-07-19): strip the dashboard to nothing, then add things
back ONE AT A TIME, checking the real hub on the real panel after every single
step. Screens, then widgets, then themes, then accents, then animated
backgrounds, then wallpapers, then orientation.

Why this exists, in test terms: it is the first coverage of the REAL hub binary
being driven incrementally over the REAL control socket, with the rendered panel
checked after each mutation. Everything else either drives a stub (the GUI
suite's ManagerHarness), or asserts store facts with nothing rendered
(tests/runtime), or changes many things at once. A build-up is what catches
"step 7 is fine alone but breaks after step 6" — coherence, not units.

Every step does three things:
  1. push ONE change over IPC,
  2. read the state back and assert the hub actually took it,
  3. grab the Edge rect to a PNG so a human can flip through the sequence.

Grabs are cropped to the Edge rect by the harness, so no other monitor is
captured.

The hub runs with an isolated XDG_CONFIG_HOME and XDG_RUNTIME_DIR, so the live
hub's config, single-instance lock and control socket are never touched.

Run:
    python3 tests/hardware/e2e_buildup.py                  # IPC + grabs
    XENEON_HW_INPUT=1 python3 tests/hardware/e2e_buildup.py  # + real touch

Output: /tmp/edge-buildup-<n>/NNN-<step>.png, one frame per step, in order.
"""
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from e2e_harness import E2E, doc, page, tile  # noqa: E402

# One widget per family we care about, in the order a user would plausibly add
# them. Deliberately spans metric widgets (need the Rust core), time widgets
# (need timers), and focus widgets (need persisted settings).
WIDGET_WALK = [
    ("clock",     "time"),
    ("cpu",       "metric"),
    ("ram",       "metric"),
    ("weather",   "network-ish"),
    ("tasks",     "productivity"),
    ("hydration", "focus"),
    ("media",     "entertainment"),
]

# Themes across every group, including the renamed inspired palettes (D3) and
# the new shipped default (D1).
THEME_WALK = ["nord", "dark", "light", "high_contrast",
              "trilby_key_check", "catppuccin", "matrix"]
# `trilby_key_check` is not a key — replaced below. Keys stayed as the distro
# spellings on purpose (see ui/qml/Theme.qml naming policy); the DISPLAY name is
# what changed. Asserting the key still works is the point of including it.
THEME_WALK[4] = "fedora"

ACCENT_WALK = ["#58A6FF", "#3FB950", "#F778BA", "#E3B341", "#000000"]
BG_WALK = ["orbs", "mesh", "aurora", "waves", "stars", "bokeh", "grid", "none"]


class BuildUp:
    def __init__(self, h):
        self.h = h
        self.n = 0
        self.frames = []

    def step(self, label, mutate, verify):
        """One atomic change: push it, read it back, grab the panel."""
        self.n += 1
        tag = "%03d-%s" % (self.n, label.replace(" ", "_").replace("/", "-"))
        try:
            mutate()
        except Exception as e:  # noqa: BLE001
            self.h.check(label, False, "mutate raised: %r" % (e,))
            return False
        time.sleep(0.45)  # let the hub apply + render before we read and grab
        st = self.h.get_state()
        ok, detail = verify(st)
        self.h.check(label, ok, detail)
        path = os.path.join(self.h.work, tag + ".png")
        try:
            self.h.grab(path)
            self.frames.append(path)
        except Exception as e:  # noqa: BLE001
            print("    (grab failed: %r)" % (e,))
        return ok


def pages_of(st):
    return (st or {}).get("pages", []) or []


def appearance_of(st):
    return (st or {}).get("appearance", {}) or {}


def main():
    h = E2E(workdir=tempfile.mkdtemp(prefix="edge-buildup-"))
    b = BuildUp(h)
    try:
        # Seed the config BEFORE launching: without first_run_complete the hub
        # boots into the First-Run Wizard, the Dashboard never loads, and every
        # probe/grab shows the same wizard — which reads as "distance 0, the hub
        # is not on the Edge" when in fact it is, just showing another screen.
        h.write_config(doc([page("Blank", [])]))
        h.launch_hub()
        if not h.verify_target_window():
            print("!! could not verify the hub is the window on the Edge — aborting")
            return 2

        # ── 0. STRIP: remove every screen ────────────────────────────────────
        # A single empty page, because a dashboard with zero pages is not a
        # state the UI is specified to reach — "remove all screens" in the
        # Manager leaves exactly one.
        b.step("strip-to-one-empty-screen",
               lambda: h.set_state(doc([page("Blank", [])])),
               lambda st: (len(pages_of(st)) == 1 and not pages_of(st)[0].get("tiles"),
                           "pages=%d tiles=%s" % (len(pages_of(st)),
                                                  pages_of(st)[0].get("tiles") if pages_of(st) else "?")))

        # ── 1. SCREENS: add them back one at a time ──────────────────────────
        names = ["Home", "System", "Focus", "Media"]
        for i, nm in enumerate(names, start=1):
            want = i + 1  # Blank + i added

            def mut(upto=i):
                h.set_state(doc([page("Blank", [])] +
                                [page(names[k], []) for k in range(upto)]))

            def ver(st, want=want):
                got = len(pages_of(st))
                return got == want, "expected %d screens, hub reports %d" % (want, got)
            b.step("screen-add-%d-%s" % (i, nm), mut, ver)

        # ── 2. WIDGETS: one at a time onto screen "Home" ─────────────────────
        placed = []
        for i, (wtype, family) in enumerate(WIDGET_WALK, start=1):
            placed.append(tile("bu-%s" % wtype, wtype, 1, 1))

            def mut(tiles=list(placed)):
                h.set_state(doc([page("Blank", []), page("Home", tiles)]))

            def ver(st, want=i, wtype=wtype):
                pg = [p for p in pages_of(st) if p.get("name") == "Home"]
                if not pg:
                    return False, "no Home screen in hub state"
                tiles = pg[0].get("tiles", [])
                types = [t.get("type") for t in tiles]
                return (len(tiles) == want and wtype in types,
                        "want %d tiles incl %s, hub has %d: %s" % (want, wtype, len(tiles), types))
            b.step("widget-add-%d-%s" % (i, wtype), mut, ver)

        # A stable layout to mutate appearance against, from here on.
        base = [page("Blank", []), page("Home", list(placed))]

        def push_appearance(**kw):
            app = {"mode": "dark", "themeMode": "nord", "accent": "#58A6FF",
                   "bgStyle": "orbs", "animatedBg": True, "glass": 0.55,
                   "glow": True, "gridCols": 1}
            app.update(kw)
            h.set_state(doc(base, appearance=app))

        # ── 3. THEMES ────────────────────────────────────────────────────────
        for i, key in enumerate(THEME_WALK, start=1):
            b.step("theme-%d-%s" % (i, key),
                   lambda key=key: push_appearance(themeMode=key),
                   lambda st, key=key: (appearance_of(st).get("themeMode") == key,
                                        "hub themeMode=%r" % appearance_of(st).get("themeMode")))

        # ── 4. ACCENTS / palette ─────────────────────────────────────────────
        for i, acc in enumerate(ACCENT_WALK, start=1):
            b.step("accent-%d-%s" % (i, acc.lstrip("#")),
                   lambda acc=acc: push_appearance(themeMode="nord", accent=acc),
                   lambda st, acc=acc: (str(appearance_of(st).get("accent", "")).lower() == acc.lower(),
                                        "hub accent=%r" % appearance_of(st).get("accent")))

        # ── 5. ANIMATED BACKGROUNDS ──────────────────────────────────────────
        for i, style in enumerate(BG_WALK, start=1):
            b.step("bg-%d-%s" % (i, style),
                   lambda style=style: push_appearance(themeMode="nord", bgStyle=style, animatedBg=True),
                   lambda st, style=style: (appearance_of(st).get("bgStyle") == style,
                                            "hub bgStyle=%r" % appearance_of(st).get("bgStyle")))

        # animatedBg off — the calm default. Proves the switch actually gates.
        b.step("bg-animated-off",
               lambda: push_appearance(themeMode="nord", bgStyle="orbs", animatedBg=False),
               lambda st: (appearance_of(st).get("animatedBg") is False,
                           "hub animatedBg=%r" % appearance_of(st).get("animatedBg")))

        # ── 6. IMAGES / wallpaper ────────────────────────────────────────────
        for i, wp in enumerate(["midnight", "nebula", "aurora", ""], start=1):
            b.step("wallpaper-%d-%s" % (i, wp or "none"),
                   lambda wp=wp: push_appearance(themeMode="nord", wallpaper=wp),
                   lambda st, wp=wp: (appearance_of(st).get("wallpaper", "") == wp,
                                      "hub wallpaper=%r" % appearance_of(st).get("wallpaper")))

        # ── 7. ORIENTATION: forced flip, both ways, twice ────────────────────
        # Physical rotation needs a human (the sensor is on /dev/hidraw5), so
        # this forces the mode the way the Manager's orientation chip does.
        for i, mode in enumerate(["portrait", "landscape", "portrait", "landscape"], start=1):
            b.step("orientation-%d-%s" % (i, mode),
                   lambda mode=mode: push_appearance(themeMode="nord", orientation=mode),
                   lambda st, mode=mode: (appearance_of(st).get("orientation") == mode,
                                          "hub orientation=%r" % appearance_of(st).get("orientation")))

        # ── 8. COHERENCE: everything at once, then back to the shipped default
        b.step("coherence-all-changed-at-once",
               lambda: push_appearance(themeMode="matrix", accent="#3FB950",
                                       bgStyle="stars", wallpaper="", glass=0.9,
                                       glow=False, orientation="portrait"),
               lambda st: (appearance_of(st).get("themeMode") == "matrix"
                           and appearance_of(st).get("bgStyle") == "stars",
                           "hub=%r" % {k: appearance_of(st).get(k)
                                       for k in ("themeMode", "bgStyle", "accent", "orientation")}))
        b.step("back-to-shipped-defaults",
               lambda: push_appearance(),
               lambda st: (appearance_of(st).get("themeMode") == "nord",
                           "hub themeMode=%r" % appearance_of(st).get("themeMode")))

        # ── 9. survival: the hub is still alive and answering ────────────────
        h.check("hub-alive-after-buildup", h.ping(), "control socket still answering")

        print("\n%d frames written to %s" % (len(b.frames), h.work))
        passed, total = h.summary()
        return 0 if passed == total else 1
    finally:
        h.cleanup()


if __name__ == "__main__":
    sys.exit(main())
