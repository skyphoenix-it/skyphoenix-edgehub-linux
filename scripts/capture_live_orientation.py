#!/usr/bin/env python3
"""Record Manager and Hub orientation synchronization on private displays."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

import capture_live_behavior as live


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--hub", required=True, type=Path)
    parser.add_argument("--manager", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    if os.environ.get(live.CAPTURE_GATE) != "1":
        raise SystemExit("set %s=1 to authorize isolated capture" % live.CAPTURE_GATE)
    for binary in (args.hub, args.manager):
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise SystemExit("missing executable: %s" % binary)
    versions = {
        "hub": live.version_output(args.hub),
        "manager": live.version_output(args.manager),
    }
    for name, output in versions.items():
        if not output.endswith(" " + args.version):
            raise SystemExit("%s version mismatch: %s" % (name, output))

    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="edgehub-live-orientation-"))
    os.chmod(work, 0o700)
    run = live.harness.E2E(workdir=str(work))
    xvfb_hub = xvfb_manager = hub_process = manager_process = recorder = None
    pointer = None
    log_streams = []
    actions = []
    try:
        run.write_config(live.demo_state("landscape"))
        xvfb_hub, hub_display = live.start_xvfb(str(work), "720x2560x24")
        xvfb_manager, manager_display = live.start_xvfb(str(work), "1920x1080x24")

        common = dict(os.environ)
        common["QT_QPA_PLATFORM"] = "xcb"
        common["XDG_SESSION_TYPE"] = "x11"
        common["XDG_CONFIG_HOME"] = run.cfg
        common["XDG_RUNTIME_DIR"] = run.run_dir
        common.pop("WAYLAND_DISPLAY", None)

        hub_log = out / "live-orientation-hub.log"
        hub_stream = open(hub_log, "w", encoding="utf-8")
        log_streams.append(hub_stream)
        hub_process = subprocess.Popen(
            [str(args.hub.resolve())], env=dict(common, DISPLAY=hub_display),
            stdout=hub_stream, stderr=subprocess.STDOUT, start_new_session=True,
        )
        live.wait_socket(Path(run.sock))

        manager_log = out / "live-orientation-manager.log"
        manager_stream = open(manager_log, "w", encoding="utf-8")
        log_streams.append(manager_stream)
        manager_process = subprocess.Popen(
            [str(args.manager.resolve())],
            env=dict(common, DISPLAY=manager_display), stdout=manager_stream,
            stderr=subprocess.STDOUT, start_new_session=True,
        )
        rect = live.wait_manager_rect(manager_log)
        _, mx, my, mw, mh = rect
        if (mx, my, mw, mh) != (240, 40, 1440, 1000):
            raise RuntimeError("unexpected Manager geometry: %r" % (rect,))
        time.sleep(2.0)

        hub_video = out / "edgehub-live-orientation-hub-root.mp4"
        manager_video = out / "edgehub-live-orientation-manager-root.mp4"
        recorder = subprocess.Popen([
            "ffmpeg", "-hide_banner", "-loglevel", "warning", "-y",
            "-f", "x11grab", "-draw_mouse", "0", "-framerate", "30",
            "-video_size", "720x2560", "-i", hub_display,
            "-f", "x11grab", "-draw_mouse", "1", "-framerate", "30",
            "-video_size", "1920x1080", "-i", manager_display,
            "-map", "0:v", "-c:v", "libx264", "-preset", "veryfast",
            "-crf", "16", "-pix_fmt", "yuv420p", str(hub_video),
            "-map", "1:v", "-c:v", "libx264", "-preset", "veryfast",
            "-crf", "16", "-pix_fmt", "yuv420p", str(manager_video),
        ], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, text=True, start_new_session=True)
        started = time.monotonic()
        pointer = live.VirtualPointer(manager_display)

        def wait_until(second):
            remaining = started + second - time.monotonic()
            if remaining > 0:
                time.sleep(remaining)

        def act(second, name, rel_x, rel_y, debug):
            wait_until(second)
            pointer.click(mx + rel_x, my + rel_y)
            time.sleep(1.0)
            state = live.ipc(Path(run.sock), {"type": "getUiState"})
            actions.append({
                "time": round(time.monotonic() - started, 3),
                "action": name,
                "x": rel_x,
                "y": rel_y,
                "hubRotation": state.get("rotation"),
            })
            live.root_capture(manager_display, out / debug)

        pointer.move(mx + 300, my + 130, 0.2)
        act(1.5, "open Device settings", 120, 347,
            "debug-orientation-01-device-landscape.png")
        act(3.5, "set portrait orientation", 360, 369,
            "debug-orientation-02-device-portrait.png")
        act(5.5, "show portrait preview in Screens", 120, 179,
            "debug-orientation-03-preview-portrait.png")
        act(7.8, "return to Device settings", 120, 347,
            "debug-orientation-04-device-portrait.png")
        act(9.8, "set landscape orientation", 448, 369,
            "debug-orientation-05-device-landscape.png")
        act(11.8, "show landscape preview in Screens", 120, 179,
            "debug-orientation-06-preview-landscape.png")
        wait_until(15.0)

        recorder.stdin.write("q\n")
        recorder.stdin.flush()
        recorder.wait(timeout=20)
        if recorder.returncode != 0:
            raise RuntimeError("orientation capture failed: %s" % recorder.stderr.read())
        recorder = None

        manifest = {
            "version": args.version,
            "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "captureClass": "real binaries in isolated dual Xvfb displays",
            "physicalDisplayUsed": False,
            "physicalInputUsed": False,
            "hubDisplay": "private portrait-native 720x2560 Xvfb",
            "managerDisplay": "private 1920x1080 Xvfb",
            "versions": versions,
            "hubSha256": live.sha256(args.hub),
            "managerSha256": live.sha256(args.manager),
            "managerRect": list(rect),
            "actions": actions,
            "files": {
                hub_video.name: live.sha256(hub_video),
                manager_video.name: live.sha256(manager_video),
            },
        }
        with open(out / "orientation-capture-manifest.json", "w",
                  encoding="utf-8") as stream:
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
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
        for stream in log_streams:
            stream.close()
        run.cleanup()
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
