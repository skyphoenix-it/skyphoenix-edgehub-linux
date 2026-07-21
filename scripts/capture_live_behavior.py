#!/usr/bin/env python3
"""Record real Hub and Manager behavior without touching physical displays.

The Hub and Manager run on separate private Xvfb displays while sharing one
isolated config and runtime directory. Mouse animation is injected only into the
Manager Xvfb through XTEST. Both virtual roots are recorded by one ffmpeg process
so the live Manager-to-Hub result stays synchronized.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

from Xlib import X, display
from Xlib.ext import xtest


REPO = Path(__file__).resolve().parents[1]
HARDWARE = REPO / "tests" / "hardware"
sys.path.insert(0, str(HARDWARE))

import e2e_harness as harness  # noqa: E402


CAPTURE_GATE = "XENEON_MARKETING_CAPTURE"


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def version_output(binary):
    return subprocess.run(
        [str(binary), "--version"], capture_output=True, text=True,
        check=True, timeout=10,
    ).stdout.strip()


def start_xvfb(work, geometry):
    process = subprocess.Popen(
        ["Xvfb", "-displayfd", "1", "-screen", "0", geometry,
         "-nolisten", "tcp"], cwd=work, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, start_new_session=True,
    )
    number = process.stdout.readline().strip()
    if not number or process.poll() is not None:
        error = process.stderr.read() if process.stderr else ""
        raise RuntimeError("Xvfb did not start: %s" % error.strip())
    return process, ":" + number


def appearance(orientation="landscape", theme="midnight", accent="blue"):
    return {
        "mode": "dark", "themeMode": theme, "accent": accent,
        "bgStyle": "orbs", "animatedBg": True, "glass": 0.55,
        "glow": True, "gridCols": 2, "orientation": orientation,
    }


def demo_state(orientation="landscape"):
    return harness.doc([
        harness.page("System", [
            harness.tile("demo-cpu", "cpu", "1x1"),
            harness.tile("demo-gpu", "gpu", "1x1"),
            harness.tile("demo-ram", "ram", "1x1"),
        ]),
        harness.page("Focus", [
            harness.tile("demo-focus", "focus", "1x1"),
            harness.tile("demo-tasks", "tasks", "1x2"),
        ]),
        harness.page("Glance", [
            harness.tile("demo-clock", "clock", "1x1"),
            harness.tile("demo-weather", "weather", "1x1"),
            harness.tile("demo-moon", "moon", "1x1"),
        ]),
    ], settings={
        "demo-focus": {
            "preset": "classic", "phase": "work", "running": False,
            "endEpoch": 0, "pausedRemaining": 1500, "doneToday": 2,
            "day": time.strftime("%Y-%m-%d"), "points": 8,
            "dailyGoal": 4, "rewardPoints": True, "celebrate": True,
            "autoStartBreak": False,
        },
        "demo-tasks": {"items": [
            {"text": "Review the dashboard", "done": True},
            {"text": "Ship the beta", "done": False},
        ]},
        "demo-weather": {"location": "Vienna", "unit": "c"},
    }, appearance=appearance(orientation))


def ipc(sock_path, message, timeout=5):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(str(sock_path))
    client.sendall((json.dumps(message) + "\n").encode())
    data = b""
    while b"\n" not in data:
        block = client.recv(65536)
        if not block:
            break
        data += block
    client.close()
    return json.loads(data.decode().split("\n", 1)[0])


def wait_socket(sock_path, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if sock_path.exists():
            try:
                if ipc(sock_path, {"type": "ping"}).get("type") == "pong":
                    return
            except (OSError, ValueError):
                pass
        time.sleep(0.2)
    raise RuntimeError("Hub control socket did not become ready")


def wait_manager_rect(log_path, timeout=15):
    deadline = time.time() + timeout
    pattern = __import__("re").compile(
        r'Placing Manager on "([^"]+)" at (-?\d+) , (-?\d+) (\d+) x (\d+)')
    while time.time() < deadline:
        if log_path.exists():
            match = pattern.search(log_path.read_text(errors="replace"))
            if match:
                return (match.group(1),) + tuple(int(v) for v in match.groups()[1:])
        time.sleep(0.2)
    raise RuntimeError("Manager did not report its virtual rectangle")


class VirtualPointer:
    def __init__(self, display_name):
        self.display = display.Display(display_name)
        self.x = 0
        self.y = 0

    def move(self, x, y, duration=0.55):
        steps = max(1, round(duration * 30))
        start_x, start_y = self.x, self.y
        for step in range(1, steps + 1):
            t = step / steps
            eased = t * t * (3 - 2 * t)
            px = round(start_x + (x - start_x) * eased)
            py = round(start_y + (y - start_y) * eased)
            xtest.fake_input(self.display, X.MotionNotify, x=px, y=py)
            self.display.sync()
            time.sleep(duration / steps)
        self.x, self.y = x, y

    def click(self, x, y):
        self.move(x, y)
        xtest.fake_input(self.display, X.ButtonPress, 1)
        self.display.sync()
        time.sleep(0.12)
        xtest.fake_input(self.display, X.ButtonRelease, 1)
        self.display.sync()

    def scroll_down(self, x, y, steps=6):
        self.move(x, y)
        for _ in range(steps):
            xtest.fake_input(self.display, X.ButtonPress, 5)
            xtest.fake_input(self.display, X.ButtonRelease, 5)
            self.display.sync()
            time.sleep(0.12)

    def close(self):
        self.display.close()


def root_capture(display_name, destination):
    subprocess.run(
        ["import", "-display", display_name, "-window", "root",
         str(destination)], check=True, timeout=15,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--hub", required=True, type=Path)
    parser.add_argument("--manager", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    if os.environ.get(CAPTURE_GATE) != "1":
        raise SystemExit("set %s=1 to authorize isolated capture" % CAPTURE_GATE)
    for binary in (args.hub, args.manager):
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise SystemExit("missing executable: %s" % binary)
    versions = {
        "hub": version_output(args.hub),
        "manager": version_output(args.manager),
    }
    for name, output in versions.items():
        if not output.endswith(" " + args.version):
            raise SystemExit("%s version mismatch: %s" % (name, output))

    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="edgehub-live-demo-"))
    os.chmod(work, 0o700)
    run = harness.E2E(workdir=str(work))
    xvfb_hub = xvfb_manager = hub_process = manager_process = recorder = None
    pointer = None
    log_streams = []
    actions = []
    try:
        # The real panel is portrait-native and the shipped landscape mode rotates
        # that surface. Capture the same pipeline, then transpose the root into the
        # front-facing 2560x720 view used in the film. Manager therefore receives
        # the same fixed landscape mode that the viewer sees on the Hub.
        run.write_config(demo_state("landscape"))
        xvfb_hub, hub_display = start_xvfb(str(work), "720x2560x24")
        xvfb_manager, manager_display = start_xvfb(str(work), "1920x1080x24")

        common = dict(os.environ)
        common["QT_QPA_PLATFORM"] = "xcb"
        common["XDG_SESSION_TYPE"] = "x11"
        common["XDG_CONFIG_HOME"] = run.cfg
        common["XDG_RUNTIME_DIR"] = run.run_dir
        common.pop("WAYLAND_DISPLAY", None)

        hub_env = dict(common, DISPLAY=hub_display)
        manager_env = dict(common, DISPLAY=manager_display)
        manager_env.pop("XENEON_GRAB", None)
        manager_env.pop("XENEON_TAB", None)

        hub_log = out / "live-hub.log"
        hub_stream = open(hub_log, "w", encoding="utf-8")
        log_streams.append(hub_stream)
        hub_process = subprocess.Popen(
            [str(args.hub.resolve())], env=hub_env, stdout=hub_stream,
            stderr=subprocess.STDOUT, start_new_session=True,
        )
        wait_socket(Path(run.sock))

        manager_log = out / "live-manager.log"
        manager_stream = open(manager_log, "w", encoding="utf-8")
        log_streams.append(manager_stream)
        manager_process = subprocess.Popen(
            [str(args.manager.resolve())], env=manager_env,
            stdout=manager_stream, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        rect = wait_manager_rect(manager_log)
        _, mx, my, mw, mh = rect
        if (mx, my, mw, mh) != (240, 40, 1440, 1000):
            raise RuntimeError("unexpected Manager geometry: %r" % (rect,))
        time.sleep(2.0)

        root_capture(manager_display, out / "debug-00-manager-ready.png")
        root_capture(hub_display, out / "debug-00-hub-ready.png")

        hub_video = out / "edgehub-live-hub-landscape.mp4"
        manager_video = out / "edgehub-live-manager-root.mp4"
        recorder = subprocess.Popen([
            "ffmpeg", "-hide_banner", "-loglevel", "warning", "-y",
            "-f", "x11grab", "-draw_mouse", "0", "-framerate", "30",
            "-video_size", "720x2560", "-i", hub_display,
            "-f", "x11grab", "-draw_mouse", "1", "-framerate", "30",
            "-video_size", "1920x1080", "-i", manager_display,
            "-filter_complex", "[0:v]transpose=cclock[hub]",
            "-map", "[hub]", "-c:v", "libx264", "-preset", "veryfast",
            "-crf", "16", "-pix_fmt", "yuv420p", str(hub_video),
            "-map", "1:v", "-c:v", "libx264", "-preset", "veryfast",
            "-crf", "16", "-pix_fmt", "yuv420p", str(manager_video),
        ], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, text=True, start_new_session=True)
        started = time.monotonic()
        pointer = VirtualPointer(manager_display)

        def wait_until(second):
            remaining = started + second - time.monotonic()
            if remaining > 0:
                time.sleep(remaining)

        def act(second, name, rel_x, rel_y, settle=1.4, debug=None):
            wait_until(second)
            pointer.click(mx + rel_x, my + rel_y)
            actions.append({"time": round(time.monotonic() - started, 3),
                            "action": name, "x": rel_x, "y": rel_y})
            time.sleep(settle)
            if debug:
                root_capture(manager_display, out / debug)

        def scroll(second, name, rel_x, rel_y, steps, debug=None):
            wait_until(second)
            pointer.scroll_down(mx + rel_x, my + rel_y, steps)
            actions.append({"time": round(time.monotonic() - started, 3),
                            "action": name, "x": rel_x, "y": rel_y,
                            "steps": steps})
            time.sleep(1.2)
            if debug:
                root_capture(manager_display, out / debug)

        pointer.move(mx + 300, my + 130, 0.2)
        act(2.5, "select Focus screen", 388, 131)
        act(5.5, "select Glance screen", 468, 131)
        act(8.5, "add screen", 540, 131, debug="debug-01-added-screen.png")
        act(11.5, "open Add widget", 840, 681, debug="debug-02-widget-picker.png")
        act(14.5, "add first widget", 430, 360, debug="debug-03-widget-added.png")
        act(17.5, "change screen to two columns", 1210, 483,
            debug="debug-04-two-columns.png")
        act(20.5, "open Look", 120, 235, debug="debug-05-look.png")
        act(23.5, "open Edge theme menu", 1000, 737,
            debug="debug-06-theme-menu.png")
        act(26.5, "choose Aurora Edge theme", 1000, 881,
            debug="debug-07-aurora-theme.png")
        act(29.5, "set Manager window dark", 450, 906,
            debug="debug-08-manager-dark.png")
        scroll(32.5, "scroll to accent colours", 840, 850, 2,
               debug="debug-09-scrolled-to-accents.png")
        act(35.5, "choose purple accent", 343, 810,
            debug="debug-10-purple-accent.png")
        act(38.5, "open Device settings", 120, 347,
            debug="debug-11-device.png")
        act(41.5, "enable automatic update checks", 293, 579,
            debug="debug-12-update-setting.png")
        wait_until(44.0)

        recorder.stdin.write("q\n")
        recorder.stdin.flush()
        recorder.wait(timeout=20)
        if recorder.returncode != 0:
            raise RuntimeError("ffmpeg capture failed: %s" % recorder.stderr.read())
        recorder = None

        final_state = ipc(Path(run.sock), {"type": "getUiState"})
        manifest = {
            "version": args.version,
            "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "captureClass": "real binaries in isolated dual Xvfb displays",
            "physicalDisplayUsed": False,
            "physicalInputUsed": False,
            "hubDisplay": "private portrait-native 720x2560 Xvfb, transposed to 2560x720",
            "managerDisplay": "private 1920x1080 Xvfb",
            "versions": versions,
            "hubSha256": sha256(args.hub),
            "managerSha256": sha256(args.manager),
            "managerRect": list(rect),
            "actions": actions,
            "finalPage": final_state.get("currentPage"),
            "files": {
                hub_video.name: sha256(hub_video),
                manager_video.name: sha256(manager_video),
            },
        }
        with open(out / "capture-manifest.json", "w", encoding="utf-8") as stream:
            json.dump(manifest, stream, indent=2, sort_keys=True)
            stream.write("\n")
        print(json.dumps(manifest, indent=2, sort_keys=True))
    finally:
        if recorder and recorder.poll() is None:
            try:
                recorder.stdin.write("q\n")
                recorder.stdin.flush()
                recorder.wait(timeout=5)
            except Exception:
                recorder.kill()
        if pointer:
            pointer.close()
        for process in (manager_process, hub_process, xvfb_manager, xvfb_hub):
            if process and process.poll() is None:
                try:
                    process.terminate()
                    process.wait(timeout=5)
                except (OSError, subprocess.TimeoutExpired):
                    process.kill()
        for stream in log_streams:
            stream.close()
        run.cleanup()
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
