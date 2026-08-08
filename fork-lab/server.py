#!/usr/bin/env python3
"""AIP Web3 Fork Lab API — real forge --fork-url runs on localhost."""
from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from runner import default_rpc, health, inspect_address, run_fork  # noqa: E402

HOST = os.environ.get("FORK_LAB_HOST", "127.0.0.1")
PORT = int(os.environ.get("FORK_LAB_PORT", "8787"))


def _json(handler: BaseHTTPRequestHandler, code: int, obj: dict) -> None:
    raw = json.dumps(obj, indent=2).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(raw)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")
    handler.end_headers()
    handler.wfile.write(raw)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[fork-lab] " + (fmt % args) + "\n")

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path in ("/", "/api/health"):
            return _json(self, 200, health())
        if path == "/api/default-poc":
            from runner import DEFAULT_POC

            return _json(
                self,
                200,
                {
                    "solidity": DEFAULT_POC.format(
                        target_label="0xTARGET",
                        target_addr="address(0)",
                    )
                },
            )
        return _json(self, 404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            return _json(self, 400, {"ok": False, "error": "invalid json"})

        if path == "/api/fork/inspect":
            return _json(
                self,
                200,
                inspect_address(
                    body.get("address") or "",
                    rpc=body.get("rpc") or None,
                    block=body.get("block") or None,
                ),
            )
        if path == "/api/fork/run":
            result = run_fork(
                address=body.get("address") or None,
                solidity=body.get("solidity") or None,
                rpc=body.get("rpc") or None,
                block=body.get("block") or None,
            )
            code = 200 if result.get("ok") or result.get("attestation") else 200
            return _json(self, code, result)
        return _json(self, 404, {"ok": False, "error": "not found"})


def main() -> None:
    # load .env if present
    env_path = ROOT.parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

    h = health()
    print(f"AIP Fork Lab  http://{HOST}:{PORT}")
    print(f"  forge={h['forge']} cast={h['cast']} rpc_ok={h['rpc_ok']} rpc={h['rpc_redacted']}")
    print(f"  default RPC fallback: {default_rpc()}")
    print("  POST /api/fork/run  POST /api/fork/inspect  GET /api/health")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
