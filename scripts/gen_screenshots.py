#!/usr/bin/env python3
"""Render real marketing screenshots of the hub, headless.

Drives the actual `build/xeneon-edge-hub` binary (QA-hooks build) via XENEON_GRAB,
with each curated preset dashboard + theme, at the real 720x2560 panel resolution
(or 2560x720 landscape). No mockups — these are the app rendering itself.

  python3 scripts/gen_screenshots.py                 # the curated set
  python3 scripts/gen_screenshots.py --only developer,gaming

Output: docs/marketing-site/assets/generated/<name>.png
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HUB = os.path.join(REPO, "build", "xeneon-edge-hub")
QMLTESTRUNNER = "/usr/lib/qt6/bin/qmltestrunner"
OUT_DIR = os.path.join(REPO, "docs", "marketing-site", "assets", "generated")

# Curated shots: (name, preset id, theme mode, orientation). Chosen so page 0
# renders POPULATED — system/time/focus/health widgets show live data headless,
# unlike the HTTP/JSON widgets, which honestly show a "connect a source" empty
# state. A range of themes, including two premium (Pro) ones.
SHOTS = [
    ("hero-system",       "system-monitor", "midnight",  "portrait"),
    ("gaming-synthwave",  "gaming",         "synthwave", "portrait"),  # Pro theme
    ("gaming-cyberpunk",  "gaming",         "cyberpunk", "portrait"),  # Pro theme
    ("calm-focus",        "calm-focus",     "oled",      "portrait"),
    ("health-aurora",     "health",         "aurora",    "portrait"),
    ("home-sunset",       "home-ambient",   "sunset",    "portrait"),
    ("minimal-nord",      "minimal",        "nord",      "portrait"),
    ("system-landscape",  "system-monitor", "midnight",  "landscape"),
]


def dump_presets():
    """Return {preset_id: ui_state_doc} by asking the real PresetCatalog."""
    dumper = os.path.join(REPO, "tests", "ui", "tst_dump_presets.qml")
    tmp_created = not os.path.exists(dumper)
    if tmp_created:
        open(dumper, "w").write(
            'import QtQuick\nimport QtTest\nimport "../../ui/qml" as App\n'
            'Item { App.PresetCatalog { id: presets }\n'
            '  TestCase { name: "D"; when: windowShown\n'
            '    function test_d() { var l = presets.list()\n'
            '      for (var i=0;i<l.length;i++) console.log("PRESET|"+l[i].id+"|"+JSON.stringify(presets.buildDoc(l[i].id)))\n'
            '      verify(l.length>0) } } }\n')
    try:
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_ASSUME_STDERR_HAS_CONSOLE="1")
        r = subprocess.run(
            [QMLTESTRUNNER, "-input", dumper, "-import", "ui/qml",
             "-import", "ui/qml/widgets", "-import", "tests/ui"],
            cwd=REPO, env=env, capture_output=True, text=True, timeout=120)
    finally:
        if tmp_created:
            os.remove(dumper)
    out = {}
    for line in (r.stdout + r.stderr).splitlines():
        if "PRESET|" not in line:
            continue
        rest = line.split("PRESET|", 1)[1]
        pid, _, doc = rest.partition("|")
        try:
            out[pid] = json.loads(doc)
        except Exception:
            pass
    return out


def write_config(cfg_dir, ui_state, theme):
    os.makedirs(os.path.join(cfg_dir, "xeneon-edge-hub"), exist_ok=True)
    ui = json.dumps(ui_state)
    # TOML basic string (double-quoted) with JSON escaped — robust against any
    # apostrophes a preset might carry (a single-quoted literal would break).
    ui_toml = ui.replace("\\", "\\\\").replace('"', '\\"')
    body = "\n".join([
        "schema_version = 1", "first_run_complete = true",
        'ui_state = "%s"' % ui_toml, "",
        "[display]", 'fallback_behavior = "hide"', 'starter_layout = "productivity"', "",
        "[theme]", 'mode = "%s"' % theme, 'accent_color = "#58A6FF"', "reduced_motion = false", "",
        "[startup]", "autostart = false", "reconnect_on_hotplug = true", "notify_on_disconnect = false", "",
        "[widgets]", "version = 1", "instances = []", "",
    ])
    open(os.path.join(cfg_dir, "xeneon-edge-hub", "config.toml"), "w").write(body)


def render(name, doc, theme, orientation):
    # Inject the theme into the layout's appearance (presets don't set it, to
    # preserve user colours) so the render uses it.
    doc = json.loads(json.dumps(doc))  # deep copy
    doc.setdefault("appearance", {})["themeMode"] = theme
    w, h = (720, 2560) if orientation == "portrait" else (2560, 720)

    work = tempfile.mkdtemp(prefix="shot-")
    try:
        os.makedirs(work + "/run", mode=0o700, exist_ok=True)
        write_config(work + "/config", doc, theme)
        out = os.path.join(OUT_DIR, name + ".png")
        env = dict(os.environ, XDG_CONFIG_HOME=work + "/config", XDG_RUNTIME_DIR=work + "/run",
                   QT_QPA_PLATFORM="offscreen", XENEON_GRAB=out,
                   XENEON_GRAB_W=str(w), XENEON_GRAB_H=str(h), XENEON_TAB="0")
        subprocess.run(["timeout", "20", HUB], env=env, capture_output=True, text=True)
        ok = os.path.exists(out) and os.path.getsize(out) > 5000
        print(f"  {'OK ' if ok else 'FAIL'} {name}  ({w}x{h}, {doc['appearance']['themeMode']})")
        return ok
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated shot names to render")
    args = ap.parse_args()
    if not os.path.exists(HUB):
        sys.exit(f"hub binary not found at {HUB} — build first (scripts/build.sh)")
    os.makedirs(OUT_DIR, exist_ok=True)

    print("Dumping preset layouts…")
    presets = dump_presets()
    if not presets:
        sys.exit("could not dump presets (is qmltestrunner available?)")
    print(f"  {len(presets)} presets")

    only = set(args.only.split(",")) if args.only else None
    shots = [s for s in SHOTS if not only or s[0] in only]
    print(f"Rendering {len(shots)} screenshot(s) → {os.path.relpath(OUT_DIR, REPO)}/")
    fails = 0
    for name, pid, theme, orient in shots:
        if pid not in presets:
            print(f"  SKIP {name}: no preset '{pid}'"); fails += 1; continue
        if not render(name, presets[pid], theme, orient):
            fails += 1
    print(f"\n{len(shots)-fails}/{len(shots)} rendered.")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
