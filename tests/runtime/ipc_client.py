#!/usr/bin/env python3
"""Speak the hub's real control protocol - a Manager stand-in for the scenarios.

Usage: ipc_client.py <runtime_dir> <message-json>   [--wait-secs N]

Sends one newline-delimited JSON message to $XDG_RUNTIME_DIR/xeneon-edge-hub-ctl
(the SAME path both real ends resolve through app/src/control_socket_path.h -
never name the socket literally elsewhere) and prints the hub's reply JSON.
Exit 0 on a reply, 1 on connect/timeout failure.

Why a stand-in and not the real Manager binary: the Manager only saves in
response to GUI interaction - it exposes no headless "push this layout" hook,
and adding one would be product code written to make a test pass. So the
scenarios drive the wire protocol the Manager actually speaks. This proves the
HUB half of the single-writer rule (the hub owns and performs the write); the
Manager half (it must NOT write config.toml while connected) is covered by
tests/cpp/tst_manager_backend_sync.cpp against a FakeHub.

The ack IS the save receipt: the hub's uiStateReceived handler is an EXPLICIT
Qt::DirectConnection and applyExternalUiState() calls xeneon_config_save()
BEFORE ControlServer writes the ack (app/src/config_bridge.h). So a scenario
that has read "ok" may assert on config.toml immediately - and may then kill the
hub without racing the write it is asserting.
"""
import json
import socket
import sys
import time


def main() -> None:
    runtime_dir = sys.argv[1]
    message = sys.argv[2]
    wait_secs = 10.0
    if "--wait-secs" in sys.argv:
        wait_secs = float(sys.argv[sys.argv.index("--wait-secs") + 1])

    path = runtime_dir.rstrip("/") + "/xeneon-edge-hub-ctl"

    # The hub binds its socket a moment after launch; poll rather than assume.
    deadline = time.time() + wait_secs
    sock = None
    while time.time() < deadline:
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(5.0)
            s.connect(path)
            sock = s
            break
        except (OSError, socket.error):
            time.sleep(0.1)
    if sock is None:
        print("FAIL: could not connect to %s within %.1fs" % (path, wait_secs),
              file=sys.stderr)
        sys.exit(1)

    with sock:
        sock.sendall(message.encode() + b"\n")
        # Replies are newline-delimited JSON; read until the first newline.
        buf = b""
        try:
            while b"\n" not in buf:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                buf += chunk
        except socket.timeout:
            print("FAIL: no reply within the socket timeout", file=sys.stderr)
            sys.exit(1)

    line = buf.split(b"\n", 1)[0]
    if not line:
        print("FAIL: hub closed the connection without replying", file=sys.stderr)
        sys.exit(1)
    # Re-emit compactly so shell callers can grep/parse a stable shape.
    print(json.dumps(json.loads(line.decode()), separators=(",", ":")))


if __name__ == "__main__":
    main()
