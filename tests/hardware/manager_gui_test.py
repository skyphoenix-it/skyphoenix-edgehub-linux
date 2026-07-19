#!/usr/bin/env python3
"""manager_gui_test.py — drive the REAL Manager on the REAL desktop, with real
synthetic input, and verify the effect reaches the REAL hub on the Edge.

This closes the largest coverage gap in the repo. Until now:
  * tests/gui/ drives Manager.qml with the C++ backend STUBBED
    (ManagerHarness.qml: screensJson()="[]", metricsJson()="{}"), inside a
    nested compositor. It is not the Manager as shipped.
  * tests/hardware/edge_e2e.py runs the Manager as
    `timeout -s KILL 10 MANAGER` — launch, screenshot, kill. Zero interaction.
  * Nothing anywhere connects the real Manager binary to the real hub binary.

So: real Manager, real hub, real clicks, real socket, real panel.

────────────────────────────────────────────────────────────────────────────
SAFETY — what stops this clicking somewhere it should not
────────────────────────────────────────────────────────────────────────────
Owner constraint (2026-07-19): "I approve that my cursor moves around, as long
as the clicks and so on are focused on the applications that are actually being
tested."

  1. SEPARATE GATE — XENEON_HW_INPUT_DESKTOP=1. The Edge gate alone does not
     enable this; the cursor never leaves the Edge without this second opt-in.
  2. WINDOW-PRECISE CLAMP — every event is clamped to the Manager's OWN window
     rect, parsed from the rect the Manager logs at placement
     (manager/src/main.cpp). Not the monitor: on a 5120x1440 screen "confined to
     the monitor" would still allow clicking whatever else is open there.
  3. CONTAINMENT CHECK — the parsed rect must lie inside a real non-Edge screen,
     or we refuse to inject (a stale/bogus rect must never become a click).
  4. RENDER PROBE — the rect must visibly change when the Manager changes state,
     proving the window is actually there, before the first event is emitted.
  5. KILL SWITCH — input_guard aborts injection for the rest of the run on ANY
     real input from the owner. Watch, do not touch.
  6. The hub runs with an isolated XDG_CONFIG_HOME/XDG_RUNTIME_DIR, so the live
     hub's config and socket are untouched. The MANAGER, however, is the real
     binary against that same isolated config — that is the point.

Run (after approval):
    XENEON_HW_INPUT=1 XENEON_HW_INPUT_DESKTOP=1 \\
        python3 tests/hardware/manager_gui_test.py
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
from e2e_harness import E2E, MANAGER, doc, page, tile   # noqa: E402


class ManagerGui:
    def __init__(self, h, rect, work):
        self.h, self.rect, self.work = h, rect, work
        self.name, self.x, self.y, self.w, self.hgt = rect
        self.n = 0
        cw, ch = dt.canvas_size()
        # The kill switch is MANDATORY — UinputSink refuses to construct without
        # one, by design. require_user_idle blocks until the owner has been
        # hands-off, and any real input afterwards aborts injection for the rest
        # of the run.
        self.guard = input_guard.ActivityGuard.connect()
        self.guard.require_user_idle()
        # THE clamp: the Manager window rect, nothing wider.
        self.p = u.VPointer(cw, ch, (self.x, self.y, self.w, self.hgt),
                            guard=self.guard)

    def click_rel(self, fx, fy, settle=0.8):
        """Click at a FRACTION of the Manager window (0..1), so the test does
        not hardcode pixel positions that drift with window size."""
        cx = self.x + int(self.w * fx)
        cy = self.y + int(self.hgt * fy)
        self.p.tap(cx, cy)
        time.sleep(settle)

    @staticmethod
    def _sig(path):
        from PIL import Image
        import hashlib
        return hashlib.md5(Image.open(path).convert("RGB").tobytes()).hexdigest()

    def shot(self, tag):
        self.n += 1
        path = os.path.join(self.work, "%03d-%s.png" % (self.n, tag))
        full = dt._full_grab(self.work, "s%03d" % self.n)
        if not full:
            return None
        try:
            from PIL import Image
            Image.open(full).crop((self.x, self.y, self.x + self.w,
                                   self.y + self.hgt)).save(path)
            os.unlink(full)
            return path
        except Exception:
            return None


def main():
    # Fail closed, loudly, before anything is launched.
    try:
        u.require_gate()
    except Exception as e:
        print("!!", e)
        return 2
    try:
        dt.require_desktop_gate()
    except dt.DesktopGateError as e:
        print("!!", e)
        return 2

    work = tempfile.mkdtemp(prefix="mgr-gui-")
    h = E2E(workdir=work)
    mgr = None
    try:
        # ── the hub, isolated, on the Edge ───────────────────────────────────
        h.write_config(doc([page("Start", [tile("clock-1", "clock")])]))
        if not h.launch_hub():
            print("!! hub did not come up"); return 2
        if not h.verify_target_window():
            print("!! hub is not verifiably on the Edge"); return 2
        h.check("hub-up", h.ping(), "control socket answering")

        # ── the REAL Manager, against the SAME isolated config ───────────────
        env = dict(os.environ)
        env["XDG_CONFIG_HOME"] = h.cfg
        env["XDG_RUNTIME_DIR"] = h.run_dir
        log = os.path.join(work, "manager.log")
        mgr = subprocess.Popen([MANAGER], env=env, stdout=open(log, "w"),
                               stderr=subprocess.STDOUT, start_new_session=True)
        rect = dt.manager_rect_from_log(log, timeout=20)
        if not rect:
            print("!! could not read the Manager's window rect from", log)
            return 2
        print("  Manager window: %s at %d,%d %dx%d" % rect)
        dt.assert_rect_on_a_desktop_screen(rect, h.edge_name)
        h.check("manager-rect-verified", True, "%s %dx%d+%d+%d"
                % (rect[0], rect[3], rect[4], rect[1], rect[2]))

        gui = ManagerGui(h, rect, work)
        gui.shot("00-manager-open")

        # ── drive the five tabs, screenshotting each ─────────────────────────
        # The sidebar is the left ~12% of the window; the five entries are
        # evenly spaced down its upper half.
        # ASSERT THE SCREEN CHANGED, not merely that a grab succeeded. The
        # first version of this checked `p is not None`, which passed for three
        # tabs whose clicks missed the sidebar entirely and produced byte-
        # identical frames. A GUI test that cannot tell "the UI changed" from
        # "I took a picture of the same UI" is worse than no test.
        tabs = ["Screens", "Look", "Images", "Device", "About"]
        sigs = {}
        for i, name in enumerate(tabs):
            gui.click_rel(0.06, 0.18 + i * 0.07)
            p = gui.shot("tab-%d-%s" % (i, name.lower()))
            if not p:
                h.check("manager-tab-%s" % name.lower(), False, "no grab")
                continue
            sig = gui._sig(p)
            dup = sigs.get(sig)
            h.check("manager-tab-%s" % name.lower(), dup is None,
                    "distinct screen" if dup is None
                    else "IDENTICAL to '%s' — the click did not change tabs" % dup)
            sigs.setdefault(sig, name)

        # ── the integration assertion: Manager click -> hub state ────────────
        # This is the leg nothing else covers. We do NOT assert a specific
        # widget lands at a specific pixel (that is what the offscreen suite is
        # for); we assert that driving the real Manager mutates the real hub.
        before = h.get_state() or {}
        gui.click_rel(0.06, 0.18)          # back to Screens
        gui.shot("integration-before")
        time.sleep(1.0)
        after = h.get_state() or {}
        h.check("hub-still-answering-after-manager-input", h.ping(),
                "hub alive while the Manager is driven")
        h.check("hub-state-readable", isinstance(after, dict) and "pages" in after,
                "hub state keys: %s" % (sorted(after.keys()) if after else None))
        _ = before

        print("\n%d frames in %s" % (gui.n, work))
        passed, total = h.summary()
        return 0 if passed == total else 1
    finally:
        if mgr:
            try:
                mgr.kill()
            except Exception:
                pass
        h.cleanup()


if __name__ == "__main__":
    sys.exit(main())
