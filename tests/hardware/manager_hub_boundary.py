#!/usr/bin/env python3
"""manager_hub_boundary.py — genuine Manager -> Hub, and the no-overflow boundary.

The real Manager, driven with real clicks, adding widgets via its "Add widget"
picker, with EVERY add verified on the real hub over the control socket. This is
the integration leg nothing else covered: tests/gui stubs the backend,
edge_buildup drives the hub over IPC directly (not via the Manager), and
manager_gui_test only clicks tabs.

THE BOUNDARY under test (the Manager's own words, Screens tab):
    "a screen always stays one screen (it never scrolls)."
So as widgets are added past what fits, they must SPILL TO A NEW SCREEN, never
overflow the current one. The store enforces this on the addTile() path
(DashboardStore.qml:663 — "If NOTHING fits, a NEW screen"), which is exactly the
path the Manager's picker uses — and exactly the path a raw setUiState BYPASSES
(DashboardStore.qml:332, "the store does not do capacity ... SCROLLS"). Earlier
runs pushed raw state and saw 3-of-7 widgets scroll off; that was the wrong path.

Observable assertions on the HUB after each Manager click:
  1. PROPAGATION — the hub's total widget count goes up by exactly 1. Proves the
     Manager actually drives the hub.
  2. SPILL — once widgets stop fitting, the hub's PAGE count grows. Proves
     overflow becomes a new screen.
  3. NO-OVERFLOW — no single page keeps growing forever; the first page's widget
     count plateaus, then later widgets land on later pages.

Safety: identical to manager_gui_test — XENEON_HW_INPUT_DESKTOP gate, clamp to
the Manager's own window rect, render-verified hub on the Edge, idle kill switch.

Run (after approval):
    XENEON_HW_INPUT=1 XENEON_HW_INPUT_DESKTOP=1 \\
        python3 tests/hardware/manager_hub_boundary.py
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


# Fractional positions in the Manager window, measured from a 1440x1300 capture
# of the Screens tab (tests/hardware frames). Fractions, so they survive a
# different window size.
SIDEBAR_SCREENS = (0.059, 0.126)
ADD_WIDGET_BTN = (0.74, 0.208)
# First card in the "Add a widget" picker (a centered modal grid of 150px cards).
# The picker's Network card (top-right of the grid). Deliberately NOT the CPU
# card (top-LEFT): that overlaps the left-side live preview, so if the picker
# ever failed to open, the same coordinate clicked the preview TILE and opened a
# "Configure" dialog that then blocked every following click. Network sits over
# the right column when the picker is closed — harmless, no modal.
# Two Y positions for the Network card: the normal grid, and the grid shifted
# DOWN when the "This screen is full - your next widget will start a new screen"
# banner appears (the banner proves the no-overflow boundary AND pushes the cards
# down ~0.035, which was silently making every post-full add miss).
PICKER_CARD_X = 0.62
PICKER_CARD_Y = (0.36, 0.40)


def widgets_total(st):
    return sum(len(p.get("tiles", []) or []) for p in (st or {}).get("pages", []) or [])


def page_widget_counts(st):
    return [len(p.get("tiles", []) or []) for p in (st or {}).get("pages", []) or []]


def main():
    for gate in (u.require_gate, dt.require_desktop_gate):
        try:
            gate()
        except Exception as e:  # noqa: BLE001
            print("!!", e)
            return 2
    try:
        print("  binaries under test: %s" % assert_binaries_current())
    except RuntimeError as e:
        print("!!", e)
        return 2

    work = tempfile.mkdtemp(prefix="mgr-hub-")
    h = E2E(workdir=work)
    mgr = None
    try:
        # Hub on the Edge, one empty screen, 1-column (fills fastest). PORTRAIT:
        # this test's Manager coordinates (Add widget, picker) assume the
        # beside-the-config layout; O2 moves the config BELOW the preview in
        # landscape, so pin portrait to keep the layout — and the coordinates —
        # deterministic. This test is not about orientation.
        h.write_config(doc([page("Home", [])],
                           appearance={"themeMode": "nord", "orientation": "portrait"}))
        if not h.launch_hub() or not h.verify_target_window():
            print("!! hub not verifiably on the Edge"); return 2
        h.check("hub-up", h.ping(), "control socket answering")
        # verify_target_window leaves its probe "moon" tile behind; start clean so
        # the first real add is 0 -> 1, not 1 -> 2.
        h.set_state(doc([page("Home", [])]))
        time.sleep(0.5)

        # Real Manager against the same isolated config.
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

        def click(fx, fy, settle=0.7):
            p.tap(x + int(w * fx), y + int(hgt * fy)); time.sleep(settle)

        def grab(tag):
            path = os.path.join(work, tag + ".png")
            full = dt._full_grab(work, tag)
            if full:
                try:
                    from PIL import Image
                    Image.open(full).crop((x, y, x + w, y + hgt)).save(path)
                    os.unlink(full)
                except Exception:  # noqa: BLE001
                    pass
            return path

        click(*SIDEBAR_SCREENS)         # ensure we are on the Screens tab
        grab("screens-tab")

        def add_one_widget():
            """Click Add widget -> first picker card, and WAIT for the hub total
            to actually grow. Retries once — a synthetic click can miss on real
            hardware, and a UI boundary test must not be flaky on that. Returns
            the new hub state, or None if both attempts missed."""
            before = widgets_total(h.get_state())
            for cy in PICKER_CARD_Y:       # try normal grid, then banner-shifted
                # Re-assert the Screens tab: dismisses any stray dialog and puts
                # us in a known state before opening the picker.
                click(*SIDEBAR_SCREENS, settle=0.3)
                click(*ADD_WIDGET_BTN)
                click(PICKER_CARD_X, cy, settle=0.3)
                for _ in range(15):            # up to ~3s for propagation
                    time.sleep(0.2)
                    st = h.get_state()
                    if widgets_total(st) > before:
                        return st
            return None

        MAX_ADDS = 14
        page_counts_over_time = []
        first_page_counts = []
        spilled_at = None
        landed = 0

        click(*SIDEBAR_SCREENS)
        for i in range(1, MAX_ADDS + 1):
            st = add_one_widget()
            if st is None:
                h.check("add-%02d-landed" % i, False, "both click attempts missed")
                continue
            landed += 1
            counts = page_widget_counts(st)
            page_counts_over_time.append(counts)
            first_page_counts.append(counts[0] if counts else 0)
            h.check("add-%02d-landed" % i, True,
                    "hub pages: %s (total %d)" % (counts, widgets_total(st)))
            if spilled_at is None and len(counts) > 1:
                spilled_at = i
                grab("spilled-to-new-screen")
            if i % 4 == 0:
                grab("after-%02d-adds" % i)

        final = h.get_state()
        counts = page_widget_counts(final)
        total = widgets_total(final)
        print("  final: %d widgets across %d screens: %s" % (total, len(counts), counts))

        # ── BOUNDARY assertions (the point of this test) ─────────────────────
        # A: enough adds landed to actually reach the boundary.
        h.check("enough-adds-landed", landed >= 8,
                "%d of %d Manager adds reached the hub" % (landed, MAX_ADDS))

        # B: SPILL — overflow became a NEW screen.
        h.check("boundary-spilled-to-new-screen", spilled_at is not None,
                "a 2nd screen appeared at add #%s" % spilled_at)

        # C: NO-OVERFLOW — the first screen plateaued instead of swallowing every
        #    widget. If page 1 kept growing to `total`, the Manager overflowed one
        #    screen instead of spilling. "a screen always stays one screen."
        cap = max(first_page_counts) if first_page_counts else 0
        plateaued = first_page_counts.count(cap) >= 2 and cap < total
        h.check("boundary-first-screen-plateaus", plateaued,
                "first-page counts: %s (cap %d, total %d)" % (first_page_counts, cap, total))

        # D: NO page ever exceeded the first screen's proven capacity — a direct
        #    statement of the no-overflow invariant across ALL screens.
        worst = max((max(c) for c in page_counts_over_time if c), default=0)
        h.check("boundary-no-page-exceeds-capacity", worst <= cap,
                "largest widgets-on-one-page seen = %d, capacity = %d" % (worst, cap))

        grab("manager-final")
        h.check("hub-alive-after", h.ping(), "hub still answering")

        print("\nframes in %s" % work)
        passed, total_c = h.summary()
        return 0 if passed == total_c else 1
    finally:
        if mgr:
            try:
                mgr.kill()
            except Exception:  # noqa: BLE001
                pass
        h.cleanup()


if __name__ == "__main__":
    sys.exit(main())
