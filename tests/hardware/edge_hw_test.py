#!/usr/bin/env python3
"""DEPRECATED standalone hub test on the REAL Xeneon Edge.

Prefer `edge_e2e.py` - it isolates XDG_CONFIG_HOME *and* XDG_RUNTIME_DIR and
verifies the target window before injecting. THIS script still uses the REAL
config (backup/restore) and the REAL runtime dir, and requires that no hub you
care about is running.

SAFETY: refuses to run unless BOTH are set:
  XENEON_HW_INPUT=1    (synthetic input on the live session is opt-in)
  XENEON_HW_LEGACY=1   (acknowledge the real-config/runtime footprint)
All injection is confined to the Edge rect (clamped VPointer) and guarded by
the user-activity kill switch (input_guard) - any real input aborts.
"""
import socket, json, time, os, sys, subprocess, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from uinput_touch import VPointer, detect_edge, GATE_ENV
import input_guard

_BANNER = """
================================================================================
  DEPRECATED: tests/hardware/edge_hw_test.py touches the REAL config and the
  REAL runtime dir. The safe, current suite is:

      python3 tests/hardware/edge_e2e.py            (opt-in: XENEON_HW_INPUT=1)

  It fully isolates config + runtime dir, render-verifies the hub window at
  the Edge rect before the first event, and needs no backup/restore.

  To run THIS legacy script anyway, set BOTH:
      XENEON_HW_INPUT=1  XENEON_HW_LEGACY=1
================================================================================
"""
if os.environ.get(GATE_ENV) != "1" or os.environ.get("XENEON_HW_LEGACY") != "1":
    sys.stderr.write(_BANNER)
    sys.exit(2)

HUB = os.path.join(REPO, 'build', 'xeneon-edge-hub')
CFG = os.path.expanduser('~/.config/xeneon-edge-hub/config.toml')
RUNTIME = os.environ.get('XDG_RUNTIME_DIR', '/run/user/1000')
BAK = f'/tmp/xeneon-hwtest-config.bak'

R = {'pass': True, 'checks': {}}
p = None; vp = None; guard = None

def check(name, ok, detail=None):
    R['checks'][name] = {'ok': bool(ok), **({'detail': detail} if detail is not None else {})}
    if not ok: R['pass'] = False

def find_socket():
    for c in [f'{RUNTIME}/xeneon-edge-hub-ctl', '/tmp/xeneon-edge-hub-ctl']:
        if os.path.exists(c): return c
    h = glob.glob('/tmp/**/xeneon-edge-hub-ctl', recursive=True)
    return h[0] if h else None

def ipc(sock, msg=None, raw=None, timeout=4):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(timeout); s.connect(sock)
    s.sendall(raw if raw is not None else (json.dumps(msg) + '\n').encode())
    b = b''
    try:
        while b'\n' not in b:
            d = s.recv(65536)
            if not d: break
            b += d
    except socket.timeout:
        pass
    s.close()
    return json.loads(b.split(b'\n')[0].decode()) if b'\n' in b else None

def state(sock): return json.loads(ipc(sock, {'type': 'getUiState'})['state'])
def pstats(pid):
    st = open(f'/proc/{pid}/status').read()
    rss = int([l for l in st.splitlines() if l.startswith('VmRSS')][0].split()[1])
    thr = int([l for l in st.splitlines() if l.startswith('Threads')][0].split()[1])
    return rss, thr, len(os.listdir(f'/proc/{pid}/fd'))

try:
    if not os.path.exists(HUB): sys.exit(f'hub not built: {HUB}')
    ex, ey, ew, eh, cw, ch = detect_edge()
    R['edge'] = {'geom': [ex, ey, ew, eh], 'canvas': [cw, ch]}
    def E(fx, fy): return ex + ew * fx, ey + eh * fy   # Edge-fraction -> canvas

    shutil.copy2(CFG, BAK)
    env = dict(os.environ); env['DISPLAY'] = env.get('DISPLAY', ':0')
    p = subprocess.Popen([HUB], cwd=REPO, stdout=open('/tmp/xeneon-hwtest.log', 'w'),
                         stderr=subprocess.STDOUT, env=env, start_new_session=True)
    sock = None
    for _ in range(40):
        sock = find_socket()
        if sock: break
        time.sleep(0.25)
    check('hub_launched_socket', bool(sock))
    if not sock: raise SystemExit('no control socket')
    time.sleep(3)

    # ---- IPC ----
    check('ping', (ipc(sock, {'type': 'ping'}) or {}).get('type') == 'pong')
    base_rss, base_thr, base_fds = pstats(p.pid)
    lat = []; fails = 0
    for _ in range(300):
        t0 = time.perf_counter(); r = ipc(sock, {'type': 'getUiState'}); lat.append((time.perf_counter() - t0) * 1000)
        if not r or r.get('type') != 'uiState': fails += 1
    lat.sort()
    check('ipc_latency', fails == 0 and lat[296] < 20,
          {'fails': fails, 'p50_ms': round(lat[150], 3), 'p99_ms': round(lat[296], 3)})

    # ---- robustness ----
    mal = ipc(sock, raw=b'not json\n')
    ok_mal = mal and mal.get('type') == 'error'
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(5); s.connect(sock)
        s.sendall(b'{"type":"ping","p":"' + b'A' * (9 * 1024 * 1024) + b'"}\n'); s.close()
    except Exception: pass
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect(sock); s.sendall(b'{"partial"'); s.close()
    except Exception: pass
    time.sleep(0.3)
    survived = (ipc(sock, {'type': 'ping'}) or {}).get('type') == 'pong'
    check('robust_bad_input', ok_mal and survived)

    # ---- concurrent + churn ----
    socks = []
    for _ in range(25):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(4); s.connect(sock); s.sendall(b'{"type":"ping"}\n'); socks.append(s)
    pongs = 0
    for s in socks:
        b = b''
        try:
            while b'\n' not in b:
                d = s.recv(4096)
                if not d: break
                b += d
        except socket.timeout: pass
        if b'\n' in b and json.loads(b.split(b'\n')[0]).get('type') == 'pong': pongs += 1
        s.close()
    check('concurrent_25', pongs == 25, {'pongs': pongs})
    churn = 0
    for _ in range(500):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect(sock); s.close(); churn += 1
        except Exception: pass
    check('churn_500', churn == 500)

    # ---- synthetic touch (clamped to the Edge rect + kill switch armed) ----
    guard = input_guard.ActivityGuard.connect()
    guard.require_user_idle()          # owner hands-off for >= 3s (default)
    guard.arm()                        # any real input from here on aborts
    vp = VPointer(cw, ch, (ex, ey, ew, eh), guard=guard)
    st0 = state(sock)
    # locate a focus tile on page 0 for the IPC-verifiable preset test
    focus_id = None
    if st0.get('pages'):
        for t in st0['pages'][0].get('tiles', []):
            if t.get('type') == 'focus': focus_id = t['id']; break
    vp.tap(*E(0.5, 0.129))   # tap first tile -> open its expanded overlay
    time.sleep(1.3)
    if focus_id:
        def preset(): return state(sock)['settings'].get(focus_id, {}).get('preset', '?')
        p_orig = preset(); hits = 0; seq = [('classic', 0.157), ('sprint', 0.613), ('custom', 0.836), ('deep', 0.386)]
        for name, fx in seq:
            vp.tap(*E(fx, 0.059)); time.sleep(0.9)   # preset segmented row near the top
            if preset() == name: hits += 1
        check('touch_segmented_ipc_verified', hits == len(seq), {'hits': hits, 'of': len(seq)})
        st = state(sock); st['settings'].setdefault(focus_id, {})['preset'] = p_orig
        ipc(sock, {'type': 'setUiState', 'state': json.dumps(st)})
    else:
        R['checks']['touch_segmented_ipc_verified'] = {'ok': True, 'detail': 'skipped: no focus tile on page 0'}
    vp.tap(*E(0.5, 0.98)); time.sleep(1.0)            # Done bar -> close overlay
    vp.swipe(*E(0.83, 0.5), *E(0.125, 0.5)); time.sleep(1.0)   # swipe page
    vp.swipe(*E(0.125, 0.5), *E(0.83, 0.5)); time.sleep(0.6)
    for i in range(40):                               # touch storm
        vp.tap(ex + (100 + (i * 53) % 520), ey + (200 + (i * 191) % 2200), hold=0.03)
    check('touch_storm_stable', (ipc(sock, {'type': 'ping'}) or {}).get('type') == 'pong' and p.poll() is None)

    # ---- leak comparison ----
    fin_rss, fin_thr, fin_fds = pstats(p.pid)
    check('no_fd_leak', fin_fds - base_fds <= 2, {'base': base_fds, 'final': fin_fds})
    check('no_thread_leak', fin_thr - base_thr <= 1, {'base': base_thr, 'final': fin_thr})
    R['rss_kb'] = {'base': base_rss, 'final': fin_rss}

    check('not_crashed', p.poll() is None)
    check('clean_shutdown', (ipc(sock, {'type': 'shutdown'}) or {}).get('type') == 'ok')
    for _ in range(25):
        if p.poll() is not None: break
        time.sleep(0.2)
    check('exit_zero', p.poll() == 0, {'exit': p.poll()})
except input_guard.UserActivityAbort as e:
    R['pass'] = False
    R['aborted_by_user_activity'] = str(e)
    print('KILL SWITCH: injection aborted -', e, file=sys.stderr)
finally:
    if vp: vp.close()
    if guard: guard.close()
    if p and p.poll() is None:
        try: os.killpg(os.getpgid(p.pid), 15); time.sleep(1)
        except Exception: pass
    if os.path.exists(BAK):
        shutil.copy2(BAK, CFG); os.remove(BAK); R['config_restored'] = True

print(json.dumps(R, indent=2))
sys.exit(0 if R['pass'] else 1)
