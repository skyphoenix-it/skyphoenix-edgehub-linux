#!/usr/bin/env python3
"""Loopback HTTP sink for the runtime E2E scenarios.

Usage: http_sink.py <request_log> <port_file>

Binds 127.0.0.1 on an OS-chosen port, writes the port number to <port_file>
(the "ready" signal), then appends one JSON line per received request to
<request_log>: {"method","path","auth"}. Every request is answered
200 {"value":42,"items":["a","b"]} so the HTTP/JSON widget can parse it.

This is the OBSERVATION channel for the egress scenarios: a request the hub's
NetHub gate lets through lands here (attributable, counted, with its
Authorization header); a gated request never does. Loopback needs no network
namespace and no DNS, so the scenarios run unprivileged and fast.

Runs until killed (the owning scenario script traps and kills it).
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[1]
PORT_FILE = sys.argv[2]

BODY = json.dumps({"value": 42, "items": ["a", "b"]}).encode()


class Handler(BaseHTTPRequestHandler):
    def _serve(self):
        with open(LOG, "a") as f:
            f.write(json.dumps({
                "method": self.command,
                "path": self.path,
                "auth": self.headers.get("Authorization", ""),
            }) + "\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    do_GET = _serve
    do_POST = _serve

    def log_message(self, *a):  # keep the scenario output clean
        pass


def main() -> None:
    srv = HTTPServer(("127.0.0.1", 0), Handler)
    open(LOG, "a").close()                       # log exists even with 0 hits
    with open(PORT_FILE, "w") as f:
        f.write(str(srv.server_address[1]))
    srv.serve_forever()


if __name__ == "__main__":
    main()
