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
import re
from e2e_harness import doc, page, tile

# 28 explicitly-named themes plus the "dark" default (Theme.qml applyTheme()):
# the 21 classics and the 7 distro-evoking palettes (arch..crimson) - 29 values.
# MUST stay in step with ui/qml/Theme.qml - test_style_drift() below fails the
# run if it doesn't, because a theme missing here is simply never exercised on
# the panel and the omission is otherwise silent (that is how the 7 distro
# palettes went untested after they landed). Same contract as e2e_widgets.WIDGETS.
THEMES = [
    "dark", "light", "oled", "high_contrast", "midnight", "aurora", "sunset",
    "nebula", "synthwave", "cyberpunk", "deep_forest", "deep_ocean", "ember",
    "vaporwave", "rose_gold", "matrix", "nord", "dracula", "solarized",
    "gruvbox", "catppuccin", "tokyonight",
    "arch", "cachyos", "debian", "fedora", "popos", "aubergine", "crimson",
]

# All catalogued background styles, including "none" (static gradient) and the
# character styles (arch/fedora/aubergine). MUST stay in step with
# ui/qml/BackgroundCatalog.qml - asserted by test_style_drift() below.
BG_STYLES = ["none", "orbs", "mesh", "aurora", "waves", "stars", "bokeh",
             "grid", "arch", "fedora", "aubergine"]

_REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_THEME_QML = os.path.join(_REPO, "ui", "qml", "Theme.qml")
_BG_QML = os.path.join(_REPO, "ui", "qml", "BackgroundCatalog.qml")


def theme_modes():
    """The theme values declared in Theme.qml (the product's source of truth):
    every `case "<mode>":` of applyTheme() - its only switch - plus the "dark"
    default the fall-through resolves to."""
    with open(_THEME_QML, "r", errors="replace") as f:
        cases = re.findall(r'case\s+"([a-z0-9_]+)"\s*:', f.read())
    return set(cases) | {"dark"}


def bg_styles():
    """The style keys declared in BackgroundCatalog.qml ({ v: "<key>", ... })."""
    with open(_BG_QML, "r", errors="replace") as f:
        return set(re.findall(r'\{\s*v:\s*"([a-z0-9_]+)"', f.read()))


def test_style_drift(h):
    """THEMES/BG_STYLES must cover the QML catalogs exactly - no untested
    value, no ghost. Mirrors e2e_widgets.test_catalog_drift()."""
    try:
        themes = theme_modes()
        h.check("theme_list_parsed", len(themes) > 1,
                "%d theme modes in Theme.qml" % len(themes))
        missing = sorted(themes - set(THEMES))
        extra = sorted(set(THEMES) - themes)
        h.check("themes_no_untested", not missing,
                "not exercised on hardware: %r" % missing if missing else "all covered")
        h.check("themes_no_stale", not extra,
                "in THEMES but not in Theme.qml: %r" % extra if extra else "none stale")
    except Exception as e:
        h.check("theme_drift", False, "exc: %r" % e)
    try:
        styles = bg_styles()
        h.check("bg_list_parsed", len(styles) > 1,
                "%d bg styles in BackgroundCatalog.qml" % len(styles))
        missing = sorted(styles - set(BG_STYLES))
        extra = sorted(set(BG_STYLES) - styles)
        h.check("bgs_no_untested", not missing,
                "not exercised on hardware: %r" % missing if missing else "all covered")
        h.check("bgs_no_stale", not extra,
                "in BG_STYLES but not in the catalog: %r" % extra if extra else "none stale")
    except Exception as e:
        h.check("bg_drift", False, "exc: %r" % e)


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
    # The lists above must match the QML catalogs before anything is exercised.
    test_style_drift(h)

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
