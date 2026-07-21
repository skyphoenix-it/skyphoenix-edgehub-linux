"""Pure-python synthetic touch/pointer for the real Xeneon Edge — no sudo, no
ydotool, no external libraries — HARD-CONFINED to the Edge output.

## Safety design (this is a live desktop; see README "Synthetic-input safety")

1. OPT-IN GATE — creating a real /dev/uinput device requires
   XENEON_HW_INPUT=1. Without it, construction raises InputGateError before
   the device node is even opened. `CaptureSink` (unit tests) never touches
   the kernel and is exempt.
2. STRUCTURAL CLAMP — every coordinate passes through the injector's single
   emit path, which clamps to the target rect BEFORE converting to device
   units. There is no API to emit an unclamped position; callers cannot opt
   out. Unit-testable without injection via CaptureSink.
3. PHYSICAL CONFINEMENT (preferred) — `VTouch` is a true multitouch
   (ABS_MT) touchscreen device. KWin maps touchscreens to a single output
   (`org.kde.KWin.InputDevice.outputName`, writable via DBus); after
   `map_to_output("DP-3")` + readback verification, the kernel events are
   scaled by the compositor onto the Edge ONLY — they cannot land on another
   monitor even if our geometry were wrong. (Measured on the real box: the
   Edge's own "wch.cn TouchScreen" is mapped exactly this way.)
4. KILL SWITCH — every kernel write consults an input_guard.ActivityGuard;
   real user activity raises UserActivityAbort mid-gesture. A real sink
   REFUSES to exist without a guard.
5. STALE-GEOMETRY DEFENSE — XENEON_EDGE_GEOM/XENEON_CANVAS overrides are
   cross-checked against live `kscreen-doctor` output and rejected on
   mismatch (set XENEON_GEOM_TRUST=1 only on setups without kscreen).

Two Wayland gotchas (both handled):
  * input_event on 64-bit is 24 bytes — pack '=qqHHi'.
  * A single absolute jump + immediate click does NOT register: settle first
    (move -> wait -> move -> button -> hold -> release).
"""
import os, struct, fcntl, time, subprocess, re

import input_guard

GATE_ENV = "XENEON_HW_INPUT"

EV_SYN, EV_KEY, EV_ABS = 0x00, 0x01, 0x03
SYN_REPORT = 0
BTN_LEFT, BTN_TOUCH = 0x110, 0x14A
ABS_X, ABS_Y = 0x00, 0x01
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2F, 0x35, 0x36, 0x39
INPUT_PROP_POINTER, INPUT_PROP_DIRECT = 0x00, 0x01
ABS_MAX = 65535

TOUCH_DEV_NAME = "xeneon-virt-touch"
POINTER_DEV_NAME = "xeneon-virt-pointer"


class InputGateError(RuntimeError):
    """Synthetic input was requested without the explicit opt-in."""


class OutputMappingError(RuntimeError):
    """KWin did not confirm the touchscreen->output binding."""


def require_gate():
    if os.environ.get(GATE_ENV) != "1":
        raise InputGateError(
            "synthetic input on the live session is OPT-IN: set %s=1 "
            "(see tests/hardware/README.md)" % GATE_ENV)


def _IOW(t, nr, size): return (1 << 30) | (size << 16) | (ord(t) << 8) | nr
def _IO(t, nr): return (ord(t) << 8) | nr
UI_SET_EVBIT   = _IOW('U', 100, 4)
UI_SET_KEYBIT  = _IOW('U', 101, 4)
UI_SET_ABSBIT  = _IOW('U', 103, 4)
UI_SET_PROPBIT = _IOW('U', 110, 4)
UI_DEV_CREATE  = _IO('U', 1)
UI_DEV_DESTROY = _IO('U', 2)


# ── geometry ──────────────────────────────────────────────────────────────

def parse_kscreen(text):
    """Parse `kscreen-doctor -o` into [(name, x, y, w, h), ...]."""
    text = re.sub(r'\x1b\[[0-9;]*m', '', text)   # strip ANSI colour codes
    outs, name = [], None
    for line in text.splitlines():
        m = re.search(r'Output:\s+\d+\s+(\S+)', line)
        if m:
            name = m.group(1)
        m = re.search(r'Geometry:\s+(\d+),(\d+)\s+(\d+)x(\d+)', line)
        if m and name:
            x, y, w, h = map(int, m.groups())
            outs.append((name, x, y, w, h))
    return outs


def _live_outputs(attempts=4, retry_delay=0.25):
    """Read a complete live layout, tolerating only transient KScreen faults.

    KScreen can briefly abort while KWin is removing a just-destroyed virtual
    input device.  A single empty/non-zero response is therefore retried, but
    geometry is never inferred or accepted from a failed command: callers get
    an empty list unless a later invocation exits successfully *and* parses at
    least one output.
    """
    for attempt in range(attempts):
        try:
            result = subprocess.run(['kscreen-doctor', '-o'], capture_output=True,
                                    text=True, timeout=10)
            outputs = parse_kscreen(result.stdout) if result.returncode == 0 else []
            if outputs:
                return outputs
        except (OSError, subprocess.TimeoutExpired):
            pass
        if attempt + 1 < attempts:
            time.sleep(retry_delay * (attempt + 1))
    return []


def detect_edge_ex():
    """Return (edge_name, edge_x, edge_y, edge_w, edge_h, canvas_w, canvas_h).

    Auto-detects via `kscreen-doctor -o` (KDE), preferring an output whose
    name contains XENEON/EDGE, else a tall portrait output. Env overrides
    XENEON_EDGE_GEOM="x,y,w,h" + XENEON_CANVAS="w,h" are CROSS-CHECKED
    against the live layout and REJECTED when stale — a wrong rect here is
    exactly what would send clicks into the owner's other monitors. Set
    XENEON_GEOM_TRUST=1 to skip the cross-check on setups without kscreen.
    """
    g, c = os.environ.get('XENEON_EDGE_GEOM'), os.environ.get('XENEON_CANVAS')
    outs = _live_outputs()
    if g and c:
        ex, ey, ew, eh = map(int, g.split(','))
        cw, ch = map(int, c.split(','))
        if os.environ.get('XENEON_GEOM_TRUST') != '1':
            if not outs:
                raise RuntimeError(
                    "XENEON_EDGE_GEOM set but kscreen-doctor is unavailable to "
                    "verify it; refusing a blind override (XENEON_GEOM_TRUST=1 "
                    "to accept on non-KDE setups)")
            match = next((o for o in outs if o[1:] == (ex, ey, ew, eh)), None)
            live_cw = max(x + w for _, x, y, w, h in outs)
            live_ch = max(y + h for _, x, y, w, h in outs)
            if match is None or (cw, ch) != (live_cw, live_ch):
                raise RuntimeError(
                    "STALE GEOMETRY OVERRIDE: XENEON_EDGE_GEOM=%s XENEON_CANVAS=%s "
                    "does not match the live layout %s (canvas %dx%d); refusing "
                    "to inject" % (g, c, outs, live_cw, live_ch))
            return match[0], ex, ey, ew, eh, cw, ch
        return "override", ex, ey, ew, eh, cw, ch
    if not outs:
        raise RuntimeError('could not parse kscreen-doctor; set XENEON_EDGE_GEOM/XENEON_CANVAS')
    canvas_w = max(x + w for _, x, y, w, h in outs)
    canvas_h = max(y + h for _, x, y, w, h in outs)
    edge = next((o for o in outs if re.search(r'XENEON|EDGE', o[0], re.I)), None)
    if edge is None:
        edge = min(outs, key=lambda o: o[3])  # narrowest → the portrait bar
    name, ex, ey, ew, eh = edge
    return name, ex, ey, ew, eh, canvas_w, canvas_h


def detect_edge():
    """Back-compat: (edge_x, edge_y, edge_w, edge_h, canvas_w, canvas_h)."""
    return detect_edge_ex()[1:]


# ── event sinks ───────────────────────────────────────────────────────────

class CaptureSink:
    """Records would-be events instead of injecting. Lets the clamp and the
    full gesture pipeline be unit-tested WITHOUT touching the session."""
    is_real = False

    def __init__(self):
        self.events = []      # (type, code, value)
        self.created = None   # (name, keys, absbits, props, absmax)

    def create(self, name, keys, absbits, props, absmax):
        self.created = (name, tuple(keys), tuple(absbits), tuple(props), dict(absmax))

    def emit(self, t, c, v):
        self.events.append((t, c, v))

    def close(self):
        pass


class UinputSink:
    """The ONLY path to a real kernel device. Structurally gated: refuses to
    exist without the opt-in env AND an ActivityGuard, and every write is
    structurally refused until that guard is armed. This lets KWin enumerate
    the inert device before a second idle check without opening an emission
    gap."""
    is_real = True

    def __init__(self, guard):
        require_gate()                          # gate BEFORE the device exists
        if guard is None:
            raise InputGateError("real injection requires an ActivityGuard (kill switch)")
        self.guard = guard
        self.fd = None

    def create(self, name, keys, absbits, props, absmax):
        self.fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_SYN)
        if keys:
            fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        for k in keys:
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, k)
        if absbits:
            fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_ABS)
        for a in absbits:
            fcntl.ioctl(self.fd, UI_SET_ABSBIT, a)
        for p in props:
            fcntl.ioctl(self.fd, UI_SET_PROPBIT, p)
        amax = [0] * 64
        amin = [0] * 64
        for axis, (lo, hi) in absmax.items():
            amin[axis], amax[axis] = lo, hi
        z = [0] * 64
        dev = struct.pack('=80sHHHHI' + '64i' * 4,
                          name.encode(), 0x03, 0x1234, 0x5678, 1, 0,
                          *amax, *amin, *z, *z)
        os.write(self.fd, dev)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        time.sleep(1.2)  # let the compositor enumerate the new device

    def emit(self, t, c, v):
        self.guard.require_armed()              # no kernel event before arming
        self.guard.check()                      # kill switch: abort BEFORE the write
        os.write(self.fd, struct.pack('=qqHHi', 0, 0, t, c, v))  # 24-byte input_event
        if t != EV_SYN:
            self.guard.note_emit()              # attribute the resulting activity to us

    def close(self):
        if self.fd is not None:
            try:
                fcntl.ioctl(self.fd, UI_DEV_DESTROY)
            except OSError:
                pass
            os.close(self.fd)
            self.fd = None


# ── KWin device→output mapping (DBus) ─────────────────────────────────────

def _busctl(*args, timeout=10):
    r = subprocess.run(('busctl', '--user') + args, capture_output=True,
                       text=True, timeout=timeout)
    return r.returncode, r.stdout.strip()


def kwin_find_device_path(dev_name, wait=6.0):
    """Find /org/kde/KWin/InputDevice/eventN whose `name` == dev_name."""
    deadline = time.time() + wait
    while time.time() < deadline:
        rc, out = _busctl('tree', 'org.kde.KWin')
        if rc == 0:
            for path in re.findall(r'/org/kde/KWin/InputDevice/event\d+', out):
                rc2, val = _busctl('get-property', 'org.kde.KWin', path,
                                   'org.kde.KWin.InputDevice', 'name')
                if rc2 == 0 and val == 's "%s"' % dev_name:
                    return path
        time.sleep(0.3)
    return None


def kwin_map_device_to_output(dev_name, output_name):
    """Bind a (virtual) touchscreen to one output via KWin's writable
    `outputName` property and VERIFY by reading it back. Raises
    OutputMappingError unless KWin itself confirms the binding."""
    path = kwin_find_device_path(dev_name)
    if path is None:
        raise OutputMappingError("KWin never enumerated device %r" % dev_name)
    rc, _ = _busctl('set-property', 'org.kde.KWin', path,
                    'org.kde.KWin.InputDevice', 'outputName', 's', output_name)
    if rc != 0:
        raise OutputMappingError("failed to set outputName on %s" % path)
    time.sleep(0.2)
    rc, val = _busctl('get-property', 'org.kde.KWin', path,
                      'org.kde.KWin.InputDevice', 'outputName')
    if rc != 0 or val != 's "%s"' % output_name:
        raise OutputMappingError(
            "readback mismatch on %s: got %r, want %r" % (path, val, output_name))
    return path


# ── injectors ─────────────────────────────────────────────────────────────

class _Clamped:
    """Shared clamp: the ONE place coordinates become device units."""

    def __init__(self, rect):
        rx, ry, rw, rh = rect
        if rw <= 0 or rh <= 0:
            raise ValueError("target rect must be non-empty: %r" % (rect,))
        self.rx, self.ry, self.rw, self.rh = rx, ry, rw, rh

    def clamp_canvas(self, cx, cy):
        cx = min(max(cx, self.rx), self.rx + self.rw - 1)
        cy = min(max(cy, self.ry), self.ry + self.rh - 1)
        return cx, cy

    def clamp_local(self, lx, ly):
        lx = min(max(lx, 0), self.rw - 1)
        ly = min(max(ly, 0), self.rh - 1)
        return lx, ly


class VPointer(_Clamped):
    """Absolute POINTER over the whole compositor canvas, arithmetically
    clamped to `rect`. Fallback path when VTouch output-mapping is not
    available; the clamp is unconditional and unit-tested."""

    def __init__(self, canvas_w, canvas_h, rect, guard=None, sink=None):
        super().__init__(rect)
        if not (0 <= self.rx and 0 <= self.ry
                and self.rx + self.rw <= canvas_w and self.ry + self.rh <= canvas_h):
            raise ValueError("rect %r outside canvas %dx%d" % (rect, canvas_w, canvas_h))
        self.cw, self.ch = canvas_w, canvas_h
        self.sink = sink if sink is not None else UinputSink(guard)
        self.sink.create(POINTER_DEV_NAME, keys=[BTN_LEFT], absbits=[ABS_X, ABS_Y],
                         props=[INPUT_PROP_POINTER],
                         absmax={ABS_X: (0, ABS_MAX), ABS_Y: (0, ABS_MAX)})

    def _ev(self, t, c, v): self.sink.emit(t, c, v)
    def _syn(self): self._ev(EV_SYN, SYN_REPORT, 0)

    def move(self, cx, cy):
        cx, cy = self.clamp_canvas(cx, cy)      # structural: EVERY move clamps
        ax = int(cx / self.cw * ABS_MAX); ay = int(cy / self.ch * ABS_MAX)
        self._ev(EV_ABS, ABS_X, ax); self._ev(EV_ABS, ABS_Y, ay); self._syn()

    def tap(self, cx, cy, hold=0.14):
        self.move(cx - 4, cy - 4); time.sleep(0.2)   # settle: enter/motion first
        self.move(cx, cy); time.sleep(0.2)
        self._ev(EV_KEY, BTN_LEFT, 1); self._syn(); time.sleep(hold)
        self._ev(EV_KEY, BTN_LEFT, 0); self._syn(); time.sleep(0.3)

    def swipe(self, cx0, cy0, cx1, cy1, steps=25, dur=0.4):
        self.move(cx0, cy0)
        self._ev(EV_KEY, BTN_LEFT, 1); self._syn(); time.sleep(0.02)
        for i in range(1, steps + 1):
            self.move(cx0 + (cx1 - cx0) * i / steps, cy0 + (cy1 - cy0) * i / steps)
            time.sleep(dur / steps)
        self._ev(EV_KEY, BTN_LEFT, 0); self._syn(); time.sleep(0.05)

    def close(self):
        self.sink.close()


# Device-unit transforms for a touchscreen bound to a (possibly rotated)
# output. KWin scales device (0..max) onto the output; which device axis maps
# to which logical axis depends on the output transform, so the harness
# probes the candidates with an IPC-verified tap and picks the one that hits.
_TRANSFORMS = {
    "identity": lambda fx, fy: (fx, fy),
    "rot90":    lambda fx, fy: (fy, 1.0 - fx),
    "rot180":   lambda fx, fy: (1.0 - fx, 1.0 - fy),
    "rot270":   lambda fx, fy: (1.0 - fy, fx),
}


class VTouch(_Clamped):
    """True multitouch (ABS_MT) touchscreen taking EDGE-LOCAL coordinates.

    After map_to_output(), the compositor itself scales every contact onto
    the bound output — the physical confinement layer. The arithmetic clamp
    (all coords through clamp_local) stays as the second layer, and the
    device axis range is exactly 0..ABS_MAX with the compositor mapping the
    full range onto ONE output."""

    def __init__(self, rect, guard=None, sink=None, transform="identity"):
        super().__init__(rect)
        self.transform = transform
        self._track = 0
        self.mapped_path = None
        self.sink = sink if sink is not None else UinputSink(guard)
        self.sink.create(TOUCH_DEV_NAME, keys=[BTN_TOUCH],
                         absbits=[ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_TRACKING_ID,
                                  ABS_MT_POSITION_X, ABS_MT_POSITION_Y],
                         props=[INPUT_PROP_DIRECT],
                         absmax={ABS_X: (0, ABS_MAX), ABS_Y: (0, ABS_MAX),
                                 ABS_MT_SLOT: (0, 9), ABS_MT_TRACKING_ID: (0, ABS_MAX),
                                 ABS_MT_POSITION_X: (0, ABS_MAX),
                                 ABS_MT_POSITION_Y: (0, ABS_MAX)})

    def map_to_output(self, output_name):
        """Physically bind this device to one output; raises unless KWin
        confirms. Real sinks only (capture sinks have no kernel device)."""
        if not self.sink.is_real:
            self.mapped_path = "capture://" + output_name
            return self.mapped_path
        self.mapped_path = kwin_map_device_to_output(TOUCH_DEV_NAME, output_name)
        return self.mapped_path

    def _ev(self, t, c, v): self.sink.emit(t, c, v)
    def _syn(self): self._ev(EV_SYN, SYN_REPORT, 0)

    def _dev_units(self, lx, ly):
        lx, ly = self.clamp_local(lx, ly)       # structural: EVERY contact clamps
        fx = lx / (self.rw - 1) if self.rw > 1 else 0.0
        fy = ly / (self.rh - 1) if self.rh > 1 else 0.0
        tx, ty = _TRANSFORMS[self.transform](fx, fy)
        return int(round(tx * ABS_MAX)), int(round(ty * ABS_MAX))

    def _down(self, lx, ly):
        dx, dy = self._dev_units(lx, ly)
        self._track += 1
        self._ev(EV_ABS, ABS_MT_SLOT, 0)
        self._ev(EV_ABS, ABS_MT_TRACKING_ID, self._track)
        self._ev(EV_ABS, ABS_MT_POSITION_X, dx)
        self._ev(EV_ABS, ABS_MT_POSITION_Y, dy)
        self._ev(EV_KEY, BTN_TOUCH, 1)
        self._ev(EV_ABS, ABS_X, dx); self._ev(EV_ABS, ABS_Y, dy)
        self._syn()

    def _move(self, lx, ly):
        dx, dy = self._dev_units(lx, ly)
        self._ev(EV_ABS, ABS_MT_SLOT, 0)
        self._ev(EV_ABS, ABS_MT_POSITION_X, dx)
        self._ev(EV_ABS, ABS_MT_POSITION_Y, dy)
        self._ev(EV_ABS, ABS_X, dx); self._ev(EV_ABS, ABS_Y, dy)
        self._syn()

    def _up(self):
        self._ev(EV_ABS, ABS_MT_SLOT, 0)
        self._ev(EV_ABS, ABS_MT_TRACKING_ID, -1)
        self._ev(EV_KEY, BTN_TOUCH, 0)
        self._syn()

    def tap(self, lx, ly, hold=0.12):
        self._down(lx, ly); time.sleep(hold); self._up(); time.sleep(0.3)

    def swipe(self, lx0, ly0, lx1, ly1, steps=25, dur=0.4):
        self._down(lx0, ly0); time.sleep(0.04)
        for i in range(1, steps + 1):
            self._move(lx0 + (lx1 - lx0) * i / steps, ly0 + (ly1 - ly0) * i / steps)
            time.sleep(dur / steps)
        self._up(); time.sleep(0.05)

    def close(self):
        self.sink.close()
