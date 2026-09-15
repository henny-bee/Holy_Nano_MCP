#!/usr/bin/env python3
"""
Holy Nano MCP - SSE Server Bridge
Exposes holy-nano-mcp over Model Context Protocol HTTP/SSE on http://localhost:4392/sse
"""
import argparse, asyncio, json, os, platform, sys, uuid
from typing import Dict, Optional
from aiohttp import web

DEFAULT_PORT = 4392
DEFAULT_HOST = "127.0.0.1"

# An image tool answers with a path, but a provider error can carry a whole
# HTML error page. asyncio's default 64KiB StreamReader limit turns any longer
# line into a ValueError that kills the session mid-task, so give it room.
STDOUT_LIMIT = 16 * 1024 * 1024

# SSE comments keep the connection warm and, more usefully, are how a dropped
# client is noticed while the pump is parked on readline().
KEEPALIVE_SECONDS = 15

sessions: Dict[str, "SessionContext"] = {}

class SessionContext:
    def __init__(self, session_id: str, proc: asyncio.subprocess.Process, response_stream: web.StreamResponse):
        self.session_id = session_id
        self.proc = proc
        self.response_stream = response_stream
        self.closed = False
        self.dead_reason: Optional[str] = None
        self.tasks = []

    async def send_event(self, event: str, data: str):
        if self.closed:
            return
        msg = f"event: {event}\ndata: {data}\n\n".encode("utf-8")
        try:
            await self.response_stream.write(msg)
        except Exception:
            self.closed = True

    async def send_comment(self, text: str) -> bool:
        if self.closed:
            return False
        try:
            await self.response_stream.write(f": {text}\n\n".encode("utf-8"))
            return True
        except Exception:
            self.closed = True
            return False

    async def close(self, reason: Optional[str] = None):
        self.closed = True
        if reason and not self.dead_reason:
            self.dead_reason = reason
        for t in self.tasks:
            t.cancel()
        self.tasks = []
        try:
            if self.proc.returncode is None:
                self.proc.terminate()
                try:
                    await asyncio.wait_for(self.proc.wait(), timeout=5)
                except asyncio.TimeoutError:
                    self.proc.kill()
                    await self.proc.wait()
        except Exception:
            pass

def resolve_config(base_dir: str, config_path: Optional[str]) -> Optional[str]:
    """Picks the config to launch with. The shipped configs hold credentials and
    are gitignored, so a fresh checkout may have neither - launching with a path
    that does not exist makes every tool fail on credentials instead of saying
    so once, here."""
    if config_path:
        return config_path
    for name in ("vertex.json", "gemini.json"):
        candidate = os.path.join(base_dir, "config", name)
        if os.path.isfile(candidate):
            return candidate
    return None

def to_wsl_path(path: str) -> str:
    p = path.replace("\\", "/")
    if len(p) > 1 and p[1] == ":":
        p = f"/mnt/{p[0].lower()}{p[2:]}"
    return p

def get_server_command(config_path: Optional[str] = None) -> list:
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    resolved = resolve_config(base_dir, config_path)
    if resolved is None:
        sys.stderr.write(
            "[SSE Warn] No config found in config/ - starting without one. "
            "Create config/vertex.json or config/gemini.json (see config/*.example.json).\n"
        )
    if platform.system() == "Windows":
        wsl_base = to_wsl_path(base_dir)
        cmd = ["wsl.exe", "-d", "Ubuntu", "-e", f"{wsl_base}/build/holy-nano-mcp"]
        if resolved:
            cmd.extend(["--config", to_wsl_path(resolved)])
    else:
        cmd = [os.path.join(base_dir, "build", "holy-nano-mcp")]
        if resolved:
            cmd.extend(["--config", resolved])
    return cmd

async def handle_sse(request: web.Request) -> web.StreamResponse:
    session_id = uuid.uuid4().hex
    cmd = get_server_command(request.app.get("config_path"))
    response = web.StreamResponse(
        status=200,
        headers={
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
        },
    )
    await response.prepare(request)
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            limit=STDOUT_LIMIT,
        )
    except Exception as e:
        sys.stderr.write(f"[SSE Error] Launch failed: {e}\n")
        return response

    session = SessionContext(session_id, proc, response)
    sessions[session_id] = session
    print(f"[SSE] New session created: {session_id}", flush=True)
    await session.send_event("endpoint", f"/messages?sessionId={session_id}")

    # Forward stderr in background
    async def log_stderr():
        while proc.stderr and not proc.stderr.at_eof():
            try:
                line = await proc.stderr.readline()
            except ValueError:
                continue  # over-long log line, not worth killing the session for
            if not line:
                break
            sys.stderr.write(f"[Server {session_id[:6]}] {line.decode('utf-8', 'replace')}")

    # The pump below parks on readline() for as long as a task takes to run, so
    # a client that goes away is only noticed by a write failing. Killing the
    # child on that failure is what unblocks the pump and reclaims the process.
    async def keepalive():
        while not session.closed:
            await asyncio.sleep(KEEPALIVE_SECONDS)
            if not await session.send_comment("keepalive"):
                print(f"[SSE] Client gone, stopping session: {session_id}", flush=True)
                await session.close("client disconnected")
                break

    session.tasks.append(asyncio.create_task(log_stderr()))
    session.tasks.append(asyncio.create_task(keepalive()))

    try:
        while not session.closed:
            try:
                line = await proc.stdout.readline()
            except (ValueError, asyncio.LimitOverrunError):
                session.dead_reason = f"server sent a frame larger than {STDOUT_LIMIT} bytes"
                print(f"[SSE Error] {session.dead_reason}", flush=True)
                break
            if not line:
                code = proc.returncode
                if code not in (None, 0) and not session.closed:
                    session.dead_reason = f"server process exited with code {code}"
                    print(f"[SSE Error] {session.dead_reason}", flush=True)
                break
            decoded = line.decode("utf-8", "replace").strip()
            if decoded:
                print(f"[SSE Out] -> {decoded[:80]}", flush=True)
                await session.send_event("message", decoded)
    except asyncio.CancelledError:
        session.dead_reason = "client disconnected"
        raise
    except Exception as e:
        session.dead_reason = f"bridge error: {e}"
        print(f"[SSE Exception] {e}", flush=True)
    finally:
        print(f"[SSE] Session ended: {session_id}", flush=True)
        sessions.pop(session_id, None)
        await session.close()
    return response

def rpc_error(body: bytes, message: str) -> str:
    """A JSON-RPC error carrying the id the client used, so a client that reads
    the POST body fails the call instead of waiting for an event that a dead
    session will never send."""
    request_id = None
    try:
        parsed = json.loads(body.decode("utf-8", "replace"))
        if isinstance(parsed, dict):
            request_id = parsed.get("id")
    except Exception:
        pass
    return json.dumps({
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": -32000, "message": message},
    })

async def handle_messages(request: web.Request) -> web.Response:
    cors = {"Access-Control-Allow-Origin": "*", "Content-Type": "application/json"}
    body = await request.read()
    session_id = request.query.get("sessionId")
    session = sessions.get(session_id) if session_id else None

    if session is None:
        detail = "Session not found - reconnect to /sse for a new session id"
        return web.Response(status=404, text=rpc_error(body, detail), headers=cors)
    if session.closed or session.proc.returncode is not None:
        detail = session.dead_reason or "session is no longer running"
        return web.Response(status=503, text=rpc_error(body, detail), headers=cors)
    if not body:
        return web.Response(status=400, text=rpc_error(body, "Empty body"), headers=cors)

    # The server frames on newlines, so a pretty-printed request has to be
    # collapsed back onto one line or it arrives as several broken messages.
    #
    # ensure_ascii=False is load-bearing: the server's JSON parser has no
    # \uXXXX support, so the default would turn every non-ASCII character the
    # client sent - an em dash, an accent, an emoji - into an escape the server
    # rejects with "invalid JSON". Emitting raw UTF-8 also normalises escapes a
    # client sent itself, because json.loads has already decoded them.
    try:
        frame = json.dumps(
            json.loads(body.decode("utf-8")),
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")
    except Exception:
        frame = b" ".join(body.split())

    try:
        if session.proc.stdin:
            session.proc.stdin.write(frame + b"\n")
            await session.proc.stdin.drain()
        return web.Response(status=202, text='{"status":"accepted"}', headers=cors)
    except Exception as e:
        return web.Response(status=500, text=rpc_error(body, str(e)), headers=cors)

async def handle_options(request: web.Request) -> web.Response:
    return web.Response(
        status=204,
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
    )

async def shutdown_sessions(app: web.Application):
    for session in list(sessions.values()):
        await session.close("server shutting down")
    sessions.clear()

def create_app(config_path: Optional[str] = None) -> web.Application:
    app = web.Application()
    app["config_path"] = config_path
    app.router.add_get("/holy-nano", handle_sse)
    app.router.add_get("/sse", handle_sse)
    app.router.add_post("/messages", handle_messages)
    app.router.add_route("OPTIONS", "/{tail:.*}", handle_options)
    app.on_cleanup.append(shutdown_sessions)
    return app

def main():
    parser = argparse.ArgumentParser(description="Holy Nano MCP - SSE Server")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port (default: 4392)")
    parser.add_argument("--host", type=str, default=DEFAULT_HOST, help="Host (default: 127.0.0.1)")
    parser.add_argument("--config", type=str, default=None, help="Config file")
    args = parser.parse_args()
    print(f"==================================================", flush=True)
    print(f" Holy Nano MCP SSE Server running on:", flush=True)
    print(f" -> http://{args.host}:{args.port}/holy-nano", flush=True)
    print(f"==================================================", flush=True)
    app = create_app(args.config)
    web.run_app(app, host=args.host, port=args.port)

if __name__ == "__main__":
    main()
