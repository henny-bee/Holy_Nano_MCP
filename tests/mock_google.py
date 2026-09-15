#!/usr/bin/env python3
"""Mock Google image API used by tests/run-tests.sh.

Serves both wire shapes and records each request so the test can assert on the
headers and body the HolyC client actually sent.
"""
import base64, json, os, struct, sys, zlib
from http.server import BaseHTTPRequestHandler, HTTPServer

RECORD = os.environ.get("MOCK_RECORD", "/tmp/mock_requests.jsonl")


def make_png(w=32, h=32):
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    rows = []
    for y in range(h):
        row = bytearray([0])  # filter byte
        for x in range(w):
            row += bytes(((x * 8) % 256, (y * 8) % 256, 200))
        rows.append(bytes(row))
    raw = b"".join(rows)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


PNG_B64 = base64.b64encode(make_png()).decode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _reply(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n)
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = None
        with open(RECORD, "a") as f:
            f.write(json.dumps({
                "path": self.path,
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "body": parsed,
            }) + "\n")

        if "force-error" in self.path:
            return self._reply(400, {"error": {
                "code": 400, "status": "INVALID_ARGUMENT",
                "message": "mock rejected the request"}})

        if "force-textonly" in self.path:
            return self._reply(200, {"steps": [
                {"type": "model_output", "status": "done",
                 "content": [{"type": "text", "text": "I cannot draw that"}]}]})

        if "/interactions" in self.path:
            return self._reply(200, {
                "id": "int_mock_1", "status": "completed",
                "steps": [
                    {"type": "user_input", "status": "done",
                     "content": [{"type": "text", "text": "ignored"}]},
                    {"type": "model_output", "status": "done", "content": [
                        {"type": "text", "text": "here is your image"},
                        {"type": "image", "mime_type": "image/png", "data": PNG_B64},
                    ]},
                ]})

        if ":generateContent" in self.path:
            return self._reply(200, {"candidates": [{"content": {"role": "model", "parts": [
                {"text": "here is your image"},
                {"inlineData": {"mimeType": "image/png", "data": PNG_B64}},
            ]}, "finishReason": "STOP"}]})

        return self._reply(404, {"error": {"code": 404, "status": "NOT_FOUND",
                                           "message": "unknown path"}})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
