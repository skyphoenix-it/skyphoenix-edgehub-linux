#!/usr/bin/env python3
"""Real KDE/Wayland display-lifecycle validation for the physical Edge.

This suite is intentionally disruptive and therefore separately gated. It
rotates, scales, promotes, disables, and re-enables the detected Edge output,
then restores the exact KScreen baseline in ``finally``. The Hub runs with an
isolated config and runtime directory; the user's Hub config/socket are never
used. No synthetic input is created.

Run on an attended KDE Wayland session with the Edge attached:

    XENEON_HW_DISPLAY_LIFECYCLE=1 \
      python3 tests/hardware/display_lifecycle_test.py
"""
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import desktop_target as dt  # noqa: E402
from e2e_harness import E2E, assert_binaries_current, doc, page, tile  # noqa: E402


GATE = "XENEON_HW_DISPLAY_LIFECYCLE"
ROTATION_NAMES = {
    1: "none", 2: "left", 4: "inverted", 8: "right",
    16: "flipped", 32: "flipped90", 64: "flipped180", 128: "flipped270",
}


def doctor_json():
    result = subprocess.run(["kscreen-doctor", "-j"], capture_output=True,
                            text=True, timeout=15)
    if result.returncode:
        raise RuntimeError("kscreen-doctor -j failed: " + result.stderr.strip())
    return json.loads(result.stdout)


def output_by_name(config, name):
    return next((o for o in config.get("outputs", []) if o.get("name") == name), None)


def apply_doctor(*settings):
    print("  kscreen-doctor", " ".join(settings), flush=True)
    result = subprocess.run(["kscreen-doctor", *settings], capture_output=True,
                            text=True, timeout=20)
    if result.returncode:
        raise RuntimeError("kscreen-doctor failed: " +
                           (result.stderr or result.stdout).strip())
    time.sleep(3.0)


def restore_settings(baseline):
    settings = []
    for out in baseline.get("outputs", []):
        name = out["name"]
        if not out.get("enabled"):
            settings.append("output.%s.disable" % name)
            continue
        rotation = ROTATION_NAMES.get(out.get("rotation"))
        if not rotation:
            raise RuntimeError("unsupported baseline rotation %r for %s" %
                               (out.get("rotation"), name))
        settings.extend([
            "output.%s.enable" % name,
            "output.%s.mode.%s" % (name, out["currentModeId"]),
            "output.%s.position.%d,%d" %
            (name, out["pos"]["x"], out["pos"]["y"]),
            "output.%s.rotation.%s" % (name, rotation),
            "output.%s.scale.%s" % (name, out["scale"]),
            "output.%s.priority.%s" % (name, out["priority"]),
        ])
    return settings


def current_rect(name):
    for screen in dt.screens():
        if screen[0] == name:
            return screen
    return None


def grab_full(work, tag):
    path = dt._full_grab(work, tag)
    if not path:
        raise RuntimeError("Spectacle did not produce a full-desktop grab")
    return path


def state_deltas(harness, work, tag):
    from PIL import Image

    dark = {"mode": "dark", "themeMode": "midnight", "accent": "#58A6FF",
            "bgStyle": "none", "animatedBg": False, "glass": 0.0,
            "glow": False, "gridCols": 1}
    light = dict(dark, mode="light", themeMode="light")
    pages = [page("Lifecycle", [tile("clock-life", "clock")])]
    harness.set_state(doc(pages, appearance=dark))
    a_path = grab_full(work, tag + "-dark")
    harness.set_state(doc(pages, appearance=light))
    b_path = grab_full(work, tag + "-light")
    a = Image.open(a_path).convert("RGB")
    b = Image.open(b_path).convert("RGB")
    if a.size != b.size:
        raise RuntimeError("desktop grab size changed between probe states: %r -> %r" %
                           (a.size, b.size))
    screens = dt.screens()
    logical_w = max(x + width for _, x, y, width, height in screens)
    logical_h = max(y + height for _, x, y, width, height in screens)
    # On a mixed-DPI Wayland desktop Spectacle captures a compositor framebuffer,
    # not a 1:1 logical-coordinate image. With the Edge at 125%, this host emits
    # 14336x6912 for a 7168x3456 logical canvas (exactly 2x). Cropping with raw
    # KScreen coordinates silently sampled the wrong output and reported a false
    # render failure. Derive both axes from the actual frame and current canvas.
    scale_x = a.width / logical_w
    scale_y = a.height / logical_h
    deltas = {}
    for name, x, y, w, height in screens:
        box = (round(x * scale_x), round(y * scale_y),
               round((x + w) * scale_x), round((y + height) * scale_y))
        aa = a.crop(box).resize((1, 1)).getpixel((0, 0))
        bb = b.crop(box).resize((1, 1)).getpixel((0, 0))
        deltas[name] = sum((p - q) ** 2 for p, q in zip(aa, bb)) ** 0.5
    return deltas


def log_text(harness):
    try:
        with open(os.path.join(harness.work, "hub.log"), errors="replace") as stream:
            return stream.read()
    except OSError:
        return ""


def seed_config(harness):
    harness.write_config(doc([page("Lifecycle", [tile("clock-life", "clock")])],
                             appearance={"mode": "dark", "themeMode": "midnight",
                                         "accent": "#58A6FF", "bgStyle": "none",
                                         "animatedBg": False, "glass": 0.0,
                                         "glow": False, "gridCols": 1,
                                         "orientation": "auto"}))


def main():
    if os.environ.get(GATE) != "1":
        print("!! real display lifecycle is OFF; set %s=1" % GATE)
        return 77
    if os.environ.get("XDG_SESSION_TYPE") != "wayland":
        print("!! this implementation currently requires a Wayland session")
        return 77
    if not subprocess.run(["which", "kscreen-doctor"], capture_output=True).returncode == 0:
        print("!! kscreen-doctor is unavailable")
        return 77

    print("  binaries under test: %s" % assert_binaries_current())
    baseline = doctor_json()
    edge = next((o for o in baseline.get("outputs", [])
                 if o.get("enabled") and
                 ("XENEON" in (o.get("name", "") + " " +
                                (o.get("model") or "")).upper()
                  or (o.get("size", {}).get("width"),
                      o.get("size", {}).get("height")) in
                  ((2560, 720), (720, 2560)))), None)
    if not edge:
        print("!! no enabled 2560x720 Xeneon Edge output found")
        return 77
    edge_name = edge["name"]
    work = tempfile.mkdtemp(prefix="edge-lifecycle-")
    with open(os.path.join(work, "kscreen-baseline.json"), "w") as stream:
        json.dump(baseline, stream, indent=2, sort_keys=True)
    print("  evidence directory:", work, flush=True)

    h = E2E(workdir=work)
    h2 = None
    try:
        seed_config(h)
        h.check("hub-launch", h.launch_hub(), "private control socket answering")
        h.check("initial-edge-render", state_deltas(h, work, "initial").get(edge_name, 0) > 25,
                "dark/light state visibly changed the physical Edge")

        h.stop_hub()
        h.check("hub-restart", h.launch_hub(), "clean restart with the same isolated config")
        h.check("restart-edge-render", state_deltas(h, work, "restart").get(edge_name, 0) > 25,
                "restarted Hub visibly changed the physical Edge")

        apply_doctor("output.%s.rotation.none" % edge_name,
                     "output.%s.scale.1" % edge_name)
        rect = current_rect(edge_name)
        h.check("native-landscape-geometry", rect is not None and rect[3:] == (2560, 720), rect)
        h.check("native-landscape-render", state_deltas(h, work, "landscape").get(edge_name, 0) > 25,
                "Hub remained fullscreen and reactive after rotation")

        apply_doctor("output.%s.scale.1.25" % edge_name)
        rect = current_rect(edge_name)
        h.check("fractional-scale-geometry", rect is not None and rect[3:] == (2048, 576), rect)
        h.check("fractional-scale-render", state_deltas(h, work, "scale-125").get(edge_name, 0) > 25,
                "Hub remained fullscreen and reactive at 125%")

        priorities = []
        for out in baseline["outputs"]:
            priority = 1 if out["name"] == edge_name else out["priority"] + 1
            priorities.append("output.%s.priority.%d" % (out["name"], priority))
        apply_doctor(*priorities)
        promoted = output_by_name(doctor_json(), edge_name)
        h.check("edge-primary-role", promoted is not None and promoted.get("priority") == 1,
                "priority=%r" % (promoted.get("priority") if promoted else None,))
        h.check("primary-role-render", state_deltas(h, work, "primary").get(edge_name, 0) > 25,
                "Hub stayed on the Edge when it became primary")

        apply_doctor(*restore_settings(baseline))
        h.check("portrait-restored-before-hotplug", current_rect(edge_name) is not None and
                current_rect(edge_name)[3:] == (720, 2560), current_rect(edge_name))

        apply_doctor("output.%s.disable" % edge_name)
        h.check("target-disable-keeps-hub-alive", h.proc is not None and h.proc.poll() is None and h.ping(),
                "process and private IPC survived target removal")
        removed_log = log_text(h)
        h.check("target-disable-is-detected",
                "target display removed; window hidden" in removed_log,
                "production screenRemoved handler hid before compositor fallback")

        apply_doctor(*restore_settings(baseline))
        returned_log = log_text(h)
        h.check("target-reconnect-is-detected",
                "target display returned" in returned_log,
                "production screenAdded handler matched and migrated back")
        h.check("reconnect-edge-render", state_deltas(h, work, "reconnect").get(edge_name, 0) > 25,
                "reconnected Hub visibly changed the physical Edge")

        h.cleanup()
        h2 = E2E(workdir=os.path.join(work, "missing-target"))
        seed_config(h2)
        config_path = os.path.join(h2.cfg, "xeneon-edge-hub", "config.toml")
        with open(config_path, "r", encoding="utf-8") as stream:
            body = stream.read()
        body = body.replace("[display]\n", "[display]\ntarget_connector = \"NO-SUCH-DP\"\n"
                            "target_model = \"NO SUCH DISPLAY\"\n", 1)
        with open(config_path, "w", encoding="utf-8") as stream:
            stream.write(body)
        h2.check("missing-target-launch", h2.launch_hub(),
                 "hidden Hub still exposes its private control socket")
        missing_log = log_text(h2)
        h2.check("missing-target-stays-hidden",
                 "configured target display is not attached; keeping window" in missing_log,
                 "no primary-screen fallback")
        missing_deltas = state_deltas(h2, h2.work, "missing")
        h2.check("missing-target-no-output-hijack",
                 all(delta < 25 for delta in missing_deltas.values()), missing_deltas)

        passed, total = h.summary()
        passed2, total2 = h2.summary()
        return 0 if passed == total and passed2 == total2 else 1
    finally:
        try:
            apply_doctor(*restore_settings(baseline))
        except Exception as error:  # noqa: BLE001
            print("!! CRITICAL: baseline display restore failed:", error, flush=True)
        h.cleanup()
        if h2 is not None:
            h2.cleanup()


if __name__ == "__main__":
    sys.exit(main())
