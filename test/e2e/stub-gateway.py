#!/usr/bin/env python3
"""Stub HTTPS "gateway" for the setup-guide E2E run.

Pretends to be an Anthropic Messages API gateway on 127.0.0.1 so the harness can
prove what `claude-gw` sends and where.

It records ONLY a classification of the credentials, never a value:

    DUMMY  the header carries the dummy token the harness generated
    OTHER  the header carries some other value
    NONE   the header is absent or empty

plus the request method, Host header and path (query string dropped). One JSON
object per line goes to --log. Nothing else from the request is stored. The
dummy token comes from the STUB_DUMMY_TOKEN environment variable (not argv, so
it is not in the process list either).

    STUB_DUMMY_TOKEN=... stub-gateway.py --cert c.pem --key k.pem \
        --log requests.jsonl --port-file port.txt [--port 0]

Port 0 picks a free port; the chosen port is written to --port-file once the
server is listening. Python 3.9+ standard library only (macOS ships 3.9).
"""

import argparse
import hmac
import json
import os
import ssl
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCK = threading.Lock()
CONFIG = {}


def classify(value):
    """DUMMY / OTHER / NONE for one auth header value. Never returns the value."""
    if value is None or not value.strip():
        return "NONE"
    v = value.strip()
    if v.lower().startswith("bearer "):
        v = v[7:].strip()
    if not v:
        return "NONE"
    return "DUMMY" if hmac.compare_digest(v.encode(), CONFIG["dummy"].encode()) else "OTHER"


def message_body(model):
    return {
        "id": "msg_stub",
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": [{"type": "text", "text": "ok"}],
        "stop_reason": "end_turn",
        "stop_sequence": None,
        "usage": {"input_tokens": 1, "output_tokens": 1},
    }


def sse_body(model):
    def ev(name, data):
        return "event: %s\ndata: %s\n\n" % (name, json.dumps(data))

    start = message_body(model)
    start["content"] = []
    start["usage"] = {"input_tokens": 1, "output_tokens": 1}
    return (
        ev("message_start", {"type": "message_start", "message": start})
        + ev("content_block_start", {"type": "content_block_start", "index": 0,
                                     "content_block": {"type": "text", "text": ""}})
        + ev("ping", {"type": "ping"})
        + ev("content_block_delta", {"type": "content_block_delta", "index": 0,
                                     "delta": {"type": "text_delta", "text": "ok"}})
        + ev("content_block_stop", {"type": "content_block_stop", "index": 0})
        + ev("message_delta", {"type": "message_delta",
                               "delta": {"stop_reason": "end_turn", "stop_sequence": None},
                               "usage": {"output_tokens": 1}})
        + ev("message_stop", {"type": "message_stop"})
    ).encode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # silence the default access log
        pass

    def read_body(self):
        if "chunked" in (self.headers.get("Transfer-Encoding") or "").lower():
            data = b""
            while True:
                size = int(self.rfile.readline().strip() or b"0", 16)
                if size == 0:
                    self.rfile.readline()
                    return data
                data += self.rfile.read(size)
                self.rfile.readline()
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def handle_any(self):
        raw = self.read_body()
        path = self.path.split("?", 1)[0]
        record = {
            "t": round(time.time(), 3),
            "method": self.command,
            "host": self.headers.get("Host", ""),
            "path": path,
            "x-api-key": classify(self.headers.get("x-api-key")),
            "authorization": classify(self.headers.get("Authorization")),
        }
        with LOCK:
            with open(CONFIG["log"], "a") as fh:
                fh.write(json.dumps(record) + "\n")

        if self.command == "POST" and path == "/v1/messages":
            try:
                req = json.loads(raw or b"{}")
            except ValueError:
                req = {}
            model = req.get("model") or "stub-model"
            if req.get("stream"):
                self.send(200, sse_body(model), "text/event-stream")
            else:
                self.send(200, json.dumps(message_body(model)).encode())
        elif self.command == "POST" and path == "/v1/messages/count_tokens":
            self.send(200, json.dumps({"input_tokens": 1}).encode())
        else:
            self.send(404, json.dumps({"type": "error", "error": {
                "type": "not_found_error", "message": "stub gateway: no such route"}}).encode())

    do_GET = do_POST = do_HEAD = do_PUT = do_DELETE = handle_any


class QuietServer(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        # A client that rejects the self-signed cert aborts the handshake; that
        # is expected and not worth a traceback.
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--cert", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--port-file", required=True)
    args = ap.parse_args()

    dummy = os.environ.get("STUB_DUMMY_TOKEN", "")
    if not dummy:
        sys.exit("stub-gateway: STUB_DUMMY_TOKEN is not set")
    CONFIG.update(dummy=dummy, log=args.log)
    open(args.log, "a").close()

    server = QuietServer(("127.0.0.1", args.port), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(args.cert, args.key)
    # Handshake in the handler thread, not the accept loop, so one stalled client cannot block others.
    server.socket = ctx.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
    with open(args.port_file, "w") as fh:
        fh.write(str(server.server_address[1]))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
