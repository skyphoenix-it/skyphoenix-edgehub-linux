#!/usr/bin/env python3
"""Shared harness for the real-hardware E2E suite (Xeneon Edge + Manager).

Provides: launch/stop the hub on the real Edge with an ISOLATED XDG_CONFIG_HOME
*and* an ISOLATED XDG_RUNTIME_DIR (so the user's live config, single-instance
lock and control socket are never touched), IPC (get/set UI state, ping),
synthetic touch via /dev/uinput (Edge-local coords), Edge screenshots (spectacle
crop), and pass/fail bookkeeping.

## Runtime-dir isolation (the stranding hazard, fixed)

The hub binds its control socket at $XDG_RUNTIME_DIR/xeneon-edge-hub-ctl
(app/src/control_socket_path.h) and its single-instance lock next to it. This
harness used to keep the REAL XDG_RUNTIME_DIR (Wayland's socket lives there),
which meant a spawned hub bound the REAL control socket and the harness's
cleanup os.remove() could strand the user's live hub — the hub keeps its
listening fd, so it looks healthy while the Manager can never reach it again.

The fix, per spawned hub:
  * XDG_RUNTIME_DIR points at a private, 0700, SHORT directory (sockaddr_un
    caps the socket path at ~107 bytes — never a deep workdir);
  * WAYLAND_DISPLAY is rewritten to an ABSOLUTE path into the real runtime
    dir. Wayland resolves an absolute WAYLAND_DISPLAY without consulting
    XDG_RUNTIME_DIR, so the hub still reaches the compositor and renders on
    the Edge while every socket/lock it creates lands in the private dir.
    (Verified on the real session: a hub launched exactly this way renders —
    grab-confirmed — with its control socket in the isolated dir.)
  * cleanup REFUSES to remove any socket it did not create: the guard checks
    the path is inside this instance's private runtime dir. There is no code
    path that removes the user's socket, even on a crashed or half-torn-down
    run.

Geometry is auto-detected via tests/hardware/uinput_touch.detect_edge()
(kscreen-doctor), overridable with XENEON_EDGE_GEOM / XENEON_CANVAS.
"""
import os, sys, time, json, socket, subprocess, shutil, datetime, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import uinput_touch as u  # noqa: E402

HUB = os.path.join(REPO, "build", "xeneon-edge-hub")
MANAGER = os.path.join(REPO, "build", "xeneon-edge-manager")

# The control socket's BASENAME — must match app/src/control_socket_path.h.
# Deliberately NOT a full path at module level any more: the old module-level
# SOCK pointed into the real XDG_RUNTIME_DIR, and everything that touched it
# (launch cleanup, stop_hub, raw IPC in the suites) operated on the LIVE hub's
# socket. The real path now only ever exists per-E2E-instance (self.sock),
# inside a runtime dir that instance owns.
SOCK_NAME = "xeneon-edge-hub-ctl"


def _abs_wayland_display(env):
    """Rewrite WAYLAND_DISPLAY to an absolute path into the REAL runtime dir.

    Wayland clients resolve a relative WAYLAND_DISPLAY against
    $XDG_RUNTIME_DIR; once we isolate that, the compositor socket would stop
    resolving. An ABSOLUTE WAYLAND_DISPLAY is used as-is (no XDG_RUNTIME_DIR
    involved), so the spawned hub keeps its compositor connection while its
    own sockets are private."""
    real_rt = os.environ.get("XDG_RUNTIME_DIR")
    wl = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
    if not os.path.isabs(wl):
        if not real_rt:
            return  # no real runtime dir to resolve against; leave untouched
        wl = os.path.join(real_rt, wl)
    env["WAYLAND_DISPLAY"] = wl


class E2E:
    def __init__(self, workdir):
        self.work = workdir
        os.makedirs(self.work, exist_ok=True)
        self.cfg = os.path.join(self.work, "cfg")
        os.makedirs(os.path.join(self.cfg, "xeneon-edge-hub"), exist_ok=True)
        # Private runtime dir for the spawned hub. mkdtemp under /tmp, NOT
        # under workdir: the socket path must stay short (sockaddr_un ~107
        # bytes) and the dir must be 0700 (mkdtemp guarantees it).
        self.run_dir = tempfile.mkdtemp(prefix="xe-e2e-rt.")
        self.sock = os.path.join(self.run_dir, SOCK_NAME)
        self.proc = None
        self.results = []           # (name, ok, detail)
        g = u.detect_edge()
        self.ex, self.ey, self.ew, self.eh, self.cw, self.ch = g
        self.vp = None
        self.today = datetime.date.today().strftime("%Y-%m-%d")

    # ── pass/fail ──────────────────────────────────────────────────────────
    def check(self, name, ok, detail=""):
        self.results.append((name, bool(ok), str(detail)))
        print(("  PASS " if ok else "  FAIL ") + name + (" -> " + str(detail) if detail else ""), flush=True)
        return ok

    def summary(self):
        p = sum(1 for _, ok, _ in self.results if ok)
        print("\n==== %d / %d checks passed ====" % (p, len(self.results)), flush=True)
        for n, ok, d in self.results:
            if not ok:
                print("   FAILED:", n, "->", d, flush=True)
        return p, len(self.results)

    # ── config seeding + launch ────────────────────────────────────────────
    def write_config(self, ui_state_obj):
        ui = json.dumps(ui_state_obj)
        assert "'" not in ui, "ui_state must not contain a single quote"
        body = "\n".join([
            "schema_version = 1", "first_run_complete = true", "ui_state = '%s'" % ui, "",
            "[display]", 'fallback_behavior = "hide"', 'starter_layout = "productivity"', "",
            "[theme]", 'mode = "dark"', 'accent_color = "#58A6FF"', "reduced_motion = false", "",
            "[startup]", "autostart = false", "reconnect_on_hotplug = true", "notify_on_disconnect = false", "",
            "[widgets]", "version = 1", "instances = []", "",
        ])
        open(os.path.join(self.cfg, "xeneon-edge-hub", "config.toml"), "w").write(body)

    def _remove_own_socket(self):
        """Remove a stale socket — ONLY ours. The guard is structural: this
        refuses any path outside the private runtime dir this instance
        created, so no bug upstream can turn it into `os.remove(<live sock>)`
        (the exact mistake that used to strand the user's running hub)."""
        sock_dir = os.path.dirname(os.path.realpath(self.sock))
        if sock_dir != os.path.realpath(self.run_dir):
            print("  REFUSING to remove socket outside our runtime dir:", self.sock, flush=True)
            return
        try:
            if os.path.exists(self.sock):
                os.remove(self.sock)
        except OSError:
            pass

    def launch_hub(self, wait=15):
        self._remove_own_socket()   # stale leftover from a crashed prior run
        env = dict(os.environ)
        env["XDG_CONFIG_HOME"] = self.cfg      # isolate config
        env["XDG_RUNTIME_DIR"] = self.run_dir  # isolate socket + lock
        _abs_wayland_display(env)              # …while keeping the compositor
        self.log = open(os.path.join(self.work, "hub.log"), "w")
        self.proc = subprocess.Popen([HUB], cwd=REPO, env=env,
                                     stdout=self.log, stderr=subprocess.STDOUT,
                                     start_new_session=True)
        deadline = time.time() + wait
        while time.time() < deadline:
            if os.path.exists(self.sock):
                try:
                    self.get_state(); return True
                except Exception:
                    pass
            time.sleep(0.3)
        return False

    def stop_hub(self):
        if self.proc:
            try:
                self.proc.terminate()
                try: self.proc.wait(timeout=3)
                except subprocess.TimeoutExpired: self.proc.kill()
            except Exception:
                pass
            self.proc = None
        self._remove_own_socket()

    def cleanup(self):
        """Remove the private runtime dir (call after the final stop_hub)."""
        self.stop_hub()
        shutil.rmtree(self.run_dir, ignore_errors=True)

    # ── IPC ────────────────────────────────────────────────────────────────
    def _ipc(self, msg, timeout=5):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(timeout); s.connect(self.sock)
        s.sendall((json.dumps(msg) + "\n").encode())
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk: break
            buf += chunk
        s.close()
        return json.loads(buf.decode().split("\n")[0])

    def ping(self):
        try: return self._ipc({"type": "ping"}).get("type") in ("pong", "ok", "ping")
        except Exception: return False

    def get_state(self):
        return json.loads(self._ipc({"type": "getUiState"})["state"])

    def set_state(self, obj):
        self._ipc({"type": "setUiState", "state": json.dumps(obj)})
        time.sleep(0.5)   # let the hub apply + render

    def settings(self):
        return self.get_state().get("settings", {})

    # ── synthetic touch (Edge-local pixels 0..ew, 0..eh) ───────────────────
    def _pointer(self):
        if self.vp is None:
            self.vp = u.VPointer(self.cw, self.ch)
            time.sleep(1.0)   # let the compositor bind the virtual pointer
        return self.vp

    def tap(self, lx, ly, settle=0.6):
        self._pointer().tap(self.ex + lx, self.ey + ly)
        time.sleep(settle)

    def swipe(self, lx0, ly0, lx1, ly1, settle=0.7):
        self._pointer().swipe(self.ex + lx0, self.ey + ly0, self.ex + lx1, self.ey + ly1)
        time.sleep(settle)

    # ── screenshots ────────────────────────────────────────────────────────
    def grab(self, path):
        full = os.path.join(self.work, "_full.png")
        subprocess.run(["spectacle", "-b", "-n", "-f", "-o", full],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            from PIL import Image
            Image.open(full).crop((self.ex, self.ey, self.ex + self.ew, self.ey + self.eh)).save(path)
            return os.path.exists(path)
        except Exception as e:
            print("  grab failed:", e); return False


# ── config helpers (build ui_state docs) ──────────────────────────────────
def page(name, tiles):
    return {"name": name, "tiles": tiles}

def tile(tid, ttype, w=1, h=1):
    return {"id": tid, "type": ttype, "w": w, "h": h}

def doc(pages, settings=None, appearance=None):
    return {"version": 1,
            "appearance": appearance or {"mode": "dark", "themeMode": "midnight",
                                         "accent": "#58A6FF", "bgStyle": "orbs",
                                         "animatedBg": True, "glass": 0.55, "glow": True, "gridCols": 1},
            "settings": settings or {},
            "pages": pages}
