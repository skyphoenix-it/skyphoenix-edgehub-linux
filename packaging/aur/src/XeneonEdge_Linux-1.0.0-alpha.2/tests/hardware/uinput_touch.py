"""Pure-python synthetic touch/pointer for the real Xeneon Edge — no sudo, no
ydotool, no external libraries.

On a KWin/Wayland session the Edge is one output within a larger compositor
canvas. We create a virtual ABSOLUTE POINTER via /dev/uinput whose 0..65535 axis
range maps to the WHOLE canvas, so a click at canvas(x, y) lands wherever we want.

Requirements:
  * /dev/uinput writable by the current user. On this box the openlinkhub/Corsair
    daemon grants that via an ACL (`getfacl /dev/uinput` → `user:<you>:rw-`).
    Otherwise add yourself to the `input` group, or run as a user with access.

Two things that WILL bite you (both handled here):
  * input_event on 64-bit is 24 bytes — pack '=qqHHi' (standard-mode 'l' is 4
    bytes, giving a 16-byte struct → write() fails with EINVAL).
  * A single absolute jump + immediate click does NOT register on Wayland. You
    must settle first: move → wait → move → button-down → hold → button-up, so the
    compositor delivers pointer enter/motion to the surface before the button.
"""
import os, struct, fcntl, time, subprocess, re

EV_SYN, EV_KEY, EV_ABS = 0x00, 0x01, 0x03
SYN_REPORT = 0
BTN_LEFT = 0x110
ABS_X, ABS_Y = 0x00, 0x01
INPUT_PROP_POINTER = 0x00
ABS_MAX = 65535


def _IOW(t, nr, size): return (1 << 30) | (size << 16) | (ord(t) << 8) | nr
def _IO(t, nr): return (ord(t) << 8) | nr
UI_SET_EVBIT   = _IOW('U', 100, 4)
UI_SET_KEYBIT  = _IOW('U', 101, 4)
UI_SET_ABSBIT  = _IOW('U', 103, 4)
UI_SET_PROPBIT = _IOW('U', 110, 4)
UI_DEV_CREATE  = _IO('U', 1)
UI_DEV_DESTROY = _IO('U', 2)


def detect_edge():
    """Return (edge_x, edge_y, edge_w, edge_h, canvas_w, canvas_h).

    Auto-detects via `kscreen-doctor -o` (KDE), preferring an output whose name
    contains XENEON/EDGE, else a tall portrait output. Override with env:
      XENEON_EDGE_GEOM="x,y,w,h"  XENEON_CANVAS="w,h"
    """
    g = os.environ.get('XENEON_EDGE_GEOM')
    c = os.environ.get('XENEON_CANVAS')
    if g and c:
        ex, ey, ew, eh = map(int, g.split(','))
        cw, ch = map(int, c.split(','))
        return ex, ey, ew, eh, cw, ch
    out = subprocess.run(['kscreen-doctor', '-o'], capture_output=True, text=True).stdout
    out = re.sub(r'\x1b\[[0-9;]*m', '', out)   # strip ANSI colour codes
    outs = []  # (name, x, y, w, h)
    name = None
    for line in out.splitlines():
        m = re.search(r'Output:\s+\d+\s+(\S+)', line)
        if m:
            name = m.group(1)
        m = re.search(r'Geometry:\s+(\d+),(\d+)\s+(\d+)x(\d+)', line)
        if m and name:
            x, y, w, h = map(int, m.groups())
            outs.append((name, x, y, w, h))
    if not outs:
        raise RuntimeError('could not parse kscreen-doctor; set XENEON_EDGE_GEOM/XENEON_CANVAS')
    canvas_w = max(x + w for _, x, y, w, h in outs)
    canvas_h = max(y + h for _, x, y, w, h in outs)
    edge = next((o for o in outs if re.search(r'XENEON|EDGE', o[0], re.I)), None)
    if edge is None:
        edge = min(outs, key=lambda o: o[3])  # narrowest → the portrait bar
    _, ex, ey, ew, eh = edge
    return ex, ey, ew, eh, canvas_w, canvas_h


class VPointer:
    def __init__(self, canvas_w, canvas_h):
        self.cw, self.ch = canvas_w, canvas_h
        self.fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
        for ev in (EV_SYN, EV_KEY, EV_ABS):
            fcntl.ioctl(self.fd, UI_SET_EVBIT, ev)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, BTN_LEFT)
        fcntl.ioctl(self.fd, UI_SET_ABSBIT, ABS_X)
        fcntl.ioctl(self.fd, UI_SET_ABSBIT, ABS_Y)
        fcntl.ioctl(self.fd, UI_SET_PROPBIT, INPUT_PROP_POINTER)
        absmax = [0] * 64; absmax[ABS_X] = ABS_MAX; absmax[ABS_Y] = ABS_MAX
        z = [0] * 64
        dev = struct.pack('=80sHHHHI' + '64i' * 4,
                          b'xeneon-virt-touch', 0x03, 0x1234, 0x5678, 1, 0,
                          *absmax, *z, *z, *z)
        os.write(self.fd, dev)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        time.sleep(1.2)  # let the compositor enumerate the new device

    def _ev(self, t, c, v):
        os.write(self.fd, struct.pack('=qqHHi', 0, 0, t, c, v))  # 24-byte input_event

    def _syn(self): self._ev(EV_SYN, SYN_REPORT, 0)

    def move(self, cx, cy):
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
        try: fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        except Exception: pass
        os.close(self.fd)
