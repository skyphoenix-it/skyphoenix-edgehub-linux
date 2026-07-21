#!/usr/bin/env python3
"""Loopback DNS + TCP sink: names and captures every egress attempt.

Runs INSIDE the hub's network namespace (see no-egress.sh). The namespace has
only `lo`, so nothing here can reach a real network even if the hub tries.

Why a sink at all, when the namespace already blocks everything: a blocked
connection is indistinguishable from a connection never attempted. Without a
resolver the hub's DNS lookup fails *before* connect(), so a phone-home would
leave no connect() to observe and the attestation would pass for the wrong
reason. The sink makes every attempt succeed far enough to be recorded, and
DNS is what attributes it to a HOSTNAME rather than an anonymous 127.0.0.1.

  * DNS (udp/53) answers every A query with 127.0.0.1 and logs the QNAME.
    The QNAME *is* the host the hub wanted to reach.
  * TCP (80/443) accepts, logs, and closes. TLS is never completed - proving
    the attempt is the goal, not reading the payload, so no cert is needed.

Both logs are append-only, one entry per line, and are the artifact a customer
re-runs. strace covers what this cannot: egress to a hard-coded IP that never
asks DNS (see no-egress.sh).

Usage: egress_sink.py <logdir>
"""
import os
import socket
import socketserver
import struct
import sys
import threading

# Privileged ports: the harness maps root inside the user namespace, so binding
# them needs no real privilege on the host.
DNS_PORT = 53
TCP_PORTS = (80, 443)
SINK_IP = "127.0.0.1"

_lock = threading.Lock()
_logdir = ""


def log(name: str, line: str) -> None:
    with _lock:
        with open(os.path.join(_logdir, name), "a") as f:
            f.write(line + "\n")
            f.flush()


def parse_qname(data: bytes) -> str:
    """Extract the QNAME from a DNS query. Labels are length-prefixed."""
    i = 12  # skip the 12-byte header
    parts = []
    while i < len(data):
        n = data[i]
        if n == 0:
            break
        parts.append(data[i + 1 : i + 1 + n].decode("ascii", "replace"))
        i += 1 + n
    return ".".join(parts)


class DNSHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        data, sock = self.request
        try:
            qname = parse_qname(data)
        except Exception:
            return
        if not qname:
            return
        # QTYPE follows the QNAME; only A/AAAA matter for attribution.
        log("dns.log", qname.lower())

        # Minimal A-record answer pointing at the sink. Only A (type 1) is
        # answered; an AAAA query gets NOERROR/no-answer, which makes glibc fall
        # back to the A record instead of retrying and doubling the log.
        tid = data[:2]
        qend = 12 + len(qname) + 2
        qtype = struct.unpack("!H", data[qend : qend + 2])[0] if len(data) >= qend + 2 else 1
        question = data[12 : qend + 4]
        if qtype != 1:
            header = tid + b"\x81\x80" + struct.pack("!HHHH", 1, 0, 0, 0)
            sock.sendto(header + question, self.client_address)
            return
        header = tid + b"\x81\x80" + struct.pack("!HHHH", 1, 1, 0, 0)
        answer = (
            b"\xc0\x0c"                       # name: pointer to the question
            + struct.pack("!HHIH", 1, 1, 60, 4)  # A, IN, ttl 60, rdlength 4
            + socket.inet_aton(SINK_IP)
        )
        sock.sendto(header + question + answer, self.client_address)


class ThreadedUDP(socketserver.ThreadingUDPServer):
    allow_reuse_address = True


class TCPHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        port = self.server.server_address[1]
        # Read whatever arrives (a plaintext GET reveals its Host header; a TLS
        # ClientHello is opaque bytes). Either way the connection itself is the
        # finding, so a short timeout must not lose it.
        self.request.settimeout(1.5)
        blob = b""
        try:
            blob = self.request.recv(4096)
        except Exception:
            pass
        host = ""
        for line in blob.split(b"\r\n"):
            if line.lower().startswith(b"host:"):
                host = line.split(b":", 1)[1].strip().decode("ascii", "replace")
                break
        log("tcp.log", "port=%d host=%s bytes=%d" % (port, host or "-", len(blob)))
        try:
            self.request.close()
        except Exception:
            pass


class ThreadedTCP(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> None:
    global _logdir
    _logdir = sys.argv[1]
    os.makedirs(_logdir, exist_ok=True)
    # Create the logs up front: "file missing" and "zero egress" must not look
    # the same to the asserter.
    for n in ("dns.log", "tcp.log"):
        open(os.path.join(_logdir, n), "a").close()

    servers = [ThreadedUDP((SINK_IP, DNS_PORT), DNSHandler)]
    for p in TCP_PORTS:
        servers.append(ThreadedTCP((SINK_IP, p), TCPHandler))
    for s in servers:
        threading.Thread(target=s.serve_forever, daemon=True).start()

    # Tell the parent the sink is listening, so the hub never starts against a
    # half-open sink and lose the first (most interesting) request.
    print("SINK READY", flush=True)
    threading.Event().wait()


if __name__ == "__main__":
    main()
