#!/usr/bin/env python3
"""E2E theming suite for the Xeneon Edge hub.

Seeds one representative multi-widget page (clock, cpu, focus, weather, tasks)
then drives every theme, every background style, a per-widget accent override,
and the glass/glow appearance toggles over the control-socket IPC, grabbing a
screenshot for each visual variant. Every step is guarded so one FAIL never
aborts the run.

The runner owns launch/stop; this module only defines run(h) and assumes the
hub is already up. Appearance changes are applied by reading the live state,
mutating appearance/settings, and pushing it back (preserving pages+settings).
"""
import os
from e2e_harness import doc, page, tile

# 21 explicitly-named themes plus the "dark" default (Theme.qml applyTheme()).
# NOTE: the source has 21 named cases + a default that resolves to "dark",
# i.e. 22 distinct theme values in total (the brief's "23" over-counts by one).
THEMES = [
    "dark", "light", "oled", "high_contrast", "midnight", "aurora", "sunset",
    "nebula", "synthwave", "cyberpunk", "deep_forest", "deep_ocean", "ember",
    "vaporwave", "rose_gold", "matrix", "nord", "dracula", "solarized",
    "gruvbox", "catppuccin", "tokyonight",
]

# 7 catalogued animated backgrounds plus "none" (no animated background).
BG_STYLES = ["orbs", "aurora", "waves", "stars", "mesh", "bokeh", "grid", "none"]


def _seed_doc(today):
    """Representative page + the settings each widget needs to render."""
    tiles = [
        tile("clock-1", "clock"),
        tile("cpu-1", "cpu"),
        tile("focus-1", "focus"),
        tile("weather-1", "weather"),
        tile("tasks-1", "tasks"),
    ]
    settings = {
        "weather-1": {"lat": 52.52, "lon": 13.405, "place": "Berlin"},
        "tasks-1": {"items": [{"text": "A", "done": False}]},
        "focus-1": {"day": today},
    }
    return doc([page("Home", tiles)], settings=settings)


def run(h):
    # Seed the representative page once.
    try:
        h.set_state(_seed_doc(h.today))
        st = h.get_state()
        ids = [t.get("id") for t in st.get("pages", [{}])[0].get("tiles", [])]
        h.check("theming_seeded", len(ids) == 5, "tiles=%r" % ids)
    except Exception as e:
        h.check("theming_seeded", False, "exc: %r" % e)

    # ── every theme: apply, verify state, grab ───────────────────────────
    for name in THEMES:
        try:
            st = h.get_state()
            st.setdefault("appearance", {})["themeMode"] = name
            h.set_state(st)
            st = h.get_state()
            applied = st.get("appearance", {}).get("themeMode")
            h.check("theme_" + name, applied == name, "themeMode=%r" % applied)
        except Exception as e:
            h.check("theme_" + name, False, "exc: %r" % e)
        try:
            path = os.path.join(h.work, "theme_%s.png" % name)
            h.check("theme_grab_" + name, h.grab(path), path)
        except Exception as e:
            h.check("theme_grab_" + name, False, "exc: %r" % e)

    # ── every background style: apply, verify state, grab ─────────────────
    for style in BG_STYLES:
        try:
            st = h.get_state()
            st.setdefault("appearance", {})["bgStyle"] = style
            h.set_state(st)
            st = h.get_state()
            applied = st.get("appearance", {}).get("bgStyle")
            h.check("bg_" + style, applied == style, "bgStyle=%r" % applied)
        except Exception as e:
            h.check("bg_" + style, False, "exc: %r" % e)
        try:
            path = os.path.join(h.work, "bg_%s.png" % style)
            h.check("bg_grab_" + style, h.grab(path), path)
        except Exception as e:
            h.check("bg_grab_" + style, False, "exc: %r" % e)

    # ── per-widget accent override (settings keyed by tile id) ────────────
    try:
        st = h.get_state()
        st.setdefault("settings", {}).setdefault("cpu-1", {})["accent"] = "#FF6AD5"
        h.set_state(st)
        st = h.get_state()
        got = st.get("settings", {}).get("cpu-1", {}).get("accent")
        h.check("accent_override_cpu", got == "#FF6AD5", "accent=%r" % got)
    except Exception as e:
        h.check("accent_override_cpu", False, "exc: %r" % e)
    try:
        path = os.path.join(h.work, "accent_cpu.png")
        h.check("accent_grab_cpu", h.grab(path), path)
    except Exception as e:
        h.check("accent_grab_cpu", False, "exc: %r" % e)

    # ── glass opacity + glow toggles: verify state each time ──────────────
    for label, val in (("glass_low", 0.2), ("glass_high", 0.9)):
        try:
            st = h.get_state()
            st.setdefault("appearance", {})["glass"] = val
            h.set_state(st)
            st = h.get_state()
            got = st.get("appearance", {}).get("glass")
            h.check(label, got == val, "glass=%r" % got)
        except Exception as e:
            h.check(label, False, "exc: %r" % e)

    for label, val in (("glow_on", True), ("glow_off", False)):
        try:
            st = h.get_state()
            st.setdefault("appearance", {})["glow"] = val
            h.set_state(st)
            st = h.get_state()
            got = st.get("appearance", {}).get("glow")
            h.check(label, got == val, "glow=%r" % got)
        except Exception as e:
            h.check(label, False, "exc: %r" % e)

    # A final grab so the last glass/glow state is captured visually.
    try:
        path = os.path.join(h.work, "glass_glow.png")
        h.check("glass_glow_grab", h.grab(path), path)
    except Exception as e:
        h.check("glass_glow_grab", False, "exc: %r" % e)
