#!/usr/bin/env python3
"""manager_reflection_test.py — HUB -> Manager reflection (the other direction).

manager_hub_boundary tests Manager -> hub (clicks in the Manager land on the
hub). This tests the reverse: a change made on the HUB must appear in the
Manager, because the Manager polls the hub every 4s (manager_backend.h, the
`pull` timer) and mirrors it.

Covers three reflections, each: change it on the hub over the control socket,
wait for the Manager to pull, grab the Manager, assert it changed.

  1. SCREENS    — add screens on the hub -> the Manager's screen chips grow.
  2. THEME      — change the theme on the hub -> the Manager preview recolours.
  3. ORIENTATION — set the hub to landscape -> the Manager PREVIEW becomes WIDE.

(3) is a KNOWN BUG the owner reported: hub horizontal shown vertical in the
Manager. The hub reports the raw SENSOR rotation (-1 with no sensor) rather than
its effective CONTENT rotation, and with no sensor the hub DEFAULTS to landscape
(main.qml contentRotation) — so the panel is landscape while the Manager, in
auto, is told "unknown" and falls back to portrait. This test is written to FAIL
until the hub reports effective rotation.

Safety identical to the other desktop tests (XENEON_HW_INPUT_DESKTOP gate, clamp
to the Manager window rect, idle kill switch).

Run:
    XENEON_HW_INPUT=1 XENEON_HW_INPUT_DESKTOP=1 \\
        python3 tests/hardware/manager_reflection_test.py
"""
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import desktop_target as dt          # noqa: E402
import input_guard                   # noqa: E402
import uinput_touch as u             # noqa: E402
from e2e_harness import (E2E, MANAGER, assert_binaries_current,  # noqa: E402
                         doc, page, tile)

SIDEBAR_SCREENS = (0.059, 0.126)
PULL = 5.0   # > the Manager's 4s pull interval, so a hub change is picked up


def preview_rect(path, win_w, win_h):
    """Bounding box (w, h) of the dark phone-mockup preview on the light Manager.

    The preview is a near-black rounded frame in the left ~45% of the window; the
    rest of that region is the cream page background. Returns (w, h) of the dark
    region's bounding box, or None if not found. Landscape -> wide, portrait ->
    tall.
    """
    from PIL import Image
    im = Image.open(path).convert("RGB")
    W, H = im.size
    x0, x1 = int(W * 0.15), int(W * 0.47)   # left band, past the sidebar
    y0, y1 = int(H * 0.12), int(H * 0.98)
    step = 4
    minx = miny = 10 ** 9
    maxx = maxy = -1
    for y in range(y0, y1, step):
        for x in range(x0, x1, step):
            r, g, b = im.getpixel((x, y))
            if r < 70 and g < 70 and b < 80:      # near-black frame/screen
                minx = min(minx, x); maxx = max(maxx, x)
                miny = min(miny, y); maxy = max(maxy, y)
    if maxx < 0:
        return None
    return (maxx - minx, maxy - miny)


def preview_center(path, win_w, win_h):
    """Centre pixel of the preview's dark bounding box, or None."""
    from PIL import Image
    im = Image.open(path).convert("RGB")
    W, H = im.size
    x0, x1 = int(W * 0.15), int(W * 0.47)
    y0, y1 = int(H * 0.12), int(H * 0.98)
    minx = miny = 10 ** 9; maxx = maxy = -1
    for y in range(y0, y1, 4):
        for x in range(x0, x1, 4):
            r, g, b = im.getpixel((x, y))
            if r < 70 and g < 70 and b < 80:
                minx = min(minx, x); maxx = max(maxx, x)
                miny = min(miny, y); maxy = max(maxy, y)
    if maxx < 0:
        return None
    return ((minx + maxx) // 2, (miny + maxy) // 2)


def main():
    for gate in (u.require_gate, dt.require_desktop_gate):
        try:
            gate()
        except Exception as e:  # noqa: BLE001
            print("!!", e); return 2
    try:
        print("  binaries under test: %s" % assert_binaries_current())
    except RuntimeError as e:
        print("!!", e); return 2

    work = tempfile.mkdtemp(prefix="mgr-refl-")
    h = E2E(workdir=work)
    mgr = None
    try:
        # Hub: a couple of visible widgets so the preview has content, auto orient.
        base_pages = [page("Home", [tile("clock-1", "clock"), tile("cpu-1", "cpu")])]
        h.write_config(doc(base_pages))
        if not h.launch_hub() or not h.verify_target_window():
            print("!! hub not verifiably on the Edge"); return 2
        h.set_state(doc(base_pages))     # clear the probe tile
        h.check("hub-up", h.ping(), "control socket answering")

        env = dict(os.environ)
        env["XDG_CONFIG_HOME"] = h.cfg
        env["XDG_RUNTIME_DIR"] = h.run_dir
        log = os.path.join(work, "manager.log")
        mgr = subprocess.Popen([MANAGER], env=env, stdout=open(log, "w"),
                               stderr=subprocess.STDOUT, start_new_session=True)
        rect = dt.manager_rect_from_log(log, timeout=20)
        if not rect:
            print("!! could not read the Manager window rect"); return 2
        dt.assert_rect_on_a_desktop_screen(rect, h.edge_name)
        name, x, y, w, hgt = rect
        print("  Manager window: %s %dx%d+%d+%d" % (name, w, hgt, x, y))

        guard = input_guard.ActivityGuard.connect()
        guard.require_user_idle()
        cw, ch = dt.canvas_size()
        p = u.VPointer(cw, ch, (x, y, w, hgt), guard=guard)
        p.tap(x + int(w * SIDEBAR_SCREENS[0]), y + int(hgt * SIDEBAR_SCREENS[1]))
        time.sleep(0.6)

        def grab(tag):
            path = os.path.join(work, tag + ".png")
            full = dt._full_grab(work, tag)
            if full:
                from PIL import Image
                Image.open(full).crop((x, y, x + w, y + hgt)).save(path)
                os.unlink(full)
            return path

        def appearance(**kw):
            a = {"themeMode": "nord", "accent": "#58A6FF", "bgStyle": "orbs",
                 "animatedBg": True, "glass": 0.55, "glow": True,
                 "gridCols": 1, "orientation": "auto"}
            a.update(kw)
            return a

        # ── 1. SCREENS reflect ───────────────────────────────────────────────
        base0 = grab("00-baseline")
        h.set_state(doc([page("Home", base_pages[0]["tiles"])] +
                        [page(n, []) for n in ("Two", "Three", "Four")]))
        time.sleep(PULL)
        after = grab("01-screens-added")
        # The sidebar screen chips live in a strip near the top; more screens =>
        # more coloured chips => that strip changes. Compare the chip strip band.
        from PIL import Image
        b_im = Image.open(base0).convert("RGB")
        a_im = Image.open(after).convert("RGB")
        # Region right of the first chip: cream when there is one screen, filled
        # by the Two/Three/Four chips after. Sensitive to chips appearing.
        band = (int(w * 0.24), int(hgt * 0.072), int(w * 0.44), int(hgt * 0.11))
        def band_sig(im):
            c = im.crop(band).resize((10, 3))
            return [c.getpixel((i, j)) for j in range(3) for i in range(10)]
        d = sum(sum((p1 - q1) ** 2 for p1, q1 in zip(a, b)) ** 0.5
                for a, b in zip(band_sig(a_im), band_sig(b_im))) / 30
        h.check("hub-screens-reflect-in-manager", d > 8,
                "chip region changed by %.0f after adding 3 screens" % d)

        # ── 2. THEME reflects ────────────────────────────────────────────────
        h.set_state(doc(base_pages, appearance=appearance(themeMode="light")))
        time.sleep(PULL)
        light = grab("02-theme-light")
        h.set_state(doc(base_pages, appearance=appearance(themeMode="matrix")))
        time.sleep(PULL)
        matrix = grab("03-theme-matrix")
        # The PREVIEW recolours between light and matrix themes.
        # Sample the CENTRE of the detected preview rect, so it works whether the
        # preview is tall or wide.
        c = preview_center(light, w, hgt)
        if c:
            lp = Image.open(light).convert("RGB").getpixel(c)
            mp = Image.open(matrix).convert("RGB").getpixel(c)
            dd = sum((a - b) ** 2 for a, b in zip(lp, mp)) ** 0.5
            h.check("hub-theme-reflects-in-manager-preview", dd > 40,
                    "preview centre %s recoloured by %.0f (light %s -> matrix %s)"
                    % (c, dd, lp, mp))
        else:
            h.check("hub-theme-reflects-in-manager-preview", False,
                    "could not locate the preview")

        # ── 3. ORIENTATION reflects (the reported bug) ───────────────────────
        h.set_state(doc(base_pages, appearance=appearance(orientation="portrait")))
        time.sleep(PULL)
        pth = grab("04-orient-portrait")
        h.set_state(doc(base_pages, appearance=appearance(orientation="landscape")))
        time.sleep(PULL)
        lsc = grab("05-orient-landscape")

        rp = preview_rect(pth, w, hgt)
        rl = preview_rect(lsc, w, hgt)
        print("  preview portrait rect=%s  landscape rect=%s" % (rp, rl))
        if rp and rl:
            h.check("manager-preview-portrait-is-tall", rp[1] > rp[0],
                    "portrait preview %dx%d (h>w expected)" % rp)
            h.check("manager-preview-landscape-is-wide", rl[0] > rl[1],
                    "landscape preview %dx%d (w>h expected) — if tall, the hub "
                    "orientation is NOT reflected in the Manager" % rl)
        else:
            h.check("manager-preview-landscape-is-wide", False,
                    "could not measure preview rects (p=%s l=%s)" % (rp, rl))

        # AUTO with no sensor: the hub defaults to LANDSCAPE, so the Manager
        # preview in auto must ALSO be wide. This is the exact reported case.
        h.set_state(doc(base_pages, appearance=appearance(orientation="auto")))
        time.sleep(PULL)
        auto = grab("06-orient-auto")
        ra = preview_rect(auto, w, hgt)
        print("  preview auto rect=%s (hub default is landscape)" % (ra,))
        if ra:
            h.check("manager-preview-auto-matches-hub-landscape", ra[0] > ra[1],
                    "auto preview %dx%d — hub defaults to landscape so this must "
                    "be wide; tall means the reported bug" % ra)

        h.check("hub-alive-after", h.ping(), "hub still answering")
        print("\nframes in %s" % work)
        passed, total = h.summary()
        return 0 if passed == total else 1
    finally:
        if mgr:
            try:
                mgr.kill()
            except Exception:  # noqa: BLE001
                pass
        h.cleanup()


if __name__ == "__main__":
    sys.exit(main())
