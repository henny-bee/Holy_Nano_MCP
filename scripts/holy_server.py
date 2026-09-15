#!/usr/bin/env python3
"""
Holy Nano MCP - SSE Server Bridge
Exposes holy-nano-mcp over Model Context Protocol HTTP/SSE on http://localhost:4392/sse
"""
import argparse, asyncio, os, platform, sys, uuid
from typing import Dict, Optional
from aiohttp import web

DEFAULT_PORT = 4392
DEFAULT_HOST = "127.0.0.1"
sessions: Dict[str, "SessionContext"] = {}

class SessionContext:
    def __init__(self, session_id: str, proc: asyncio.subprocess.Process, response_stream: web.StreamResponse):
        self.session_id = session_id
        self.proc = proc
        self.response_stream = response_stream
        self.closed = False

    async def send_event(self, event: str, data: str):
        if self.closed:
            return
        msg = f"event: {event}\ndata: {data}\n\n".encode("utf-8")
        try:
            await self.response_stream.write(msg)
        except Exception:
            self.closed = True

    async def close(self):
        self.closed = True
        try:
            if self.proc.returncode is None:
                self.proc.terminate()
                await self.proc.wait()
        except Exception:
            pass

def get_server_command(config_path: Optional[str] = None) -> list:
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if platform.system() == "Windows":
        wsl_base = base_dir.replace("\\", "/")
        if len(wsl_base) > 1 and wsl_base[1] == ":":
            wsl_base = f"/mnt/{wsl_base[0].lower()}{wsl_base[2:]}"
        cmd = ["wsl.exe", "-d", "Ubuntu", "-e", f"{wsl_base}/build/holy-nano-mcp"]
        if config_path:
            wsl_conf = config_path.replace("\\", "/")
            if len(wsl_conf) > 1 and wsl_conf[1] == ":":
                wsl_conf = f"/mnt/{wsl_conf[0].lower()}{wsl_conf[2:]}"
            cmd.extend(["--config", wsl_conf])
        else:
            cmd.extend(["--config", f"{wsl_base}/config/vertex.json"])
    else:
        cmd = [os.path.join(base_dir, "build", "holy-nano-mcp")]
        cmd.extend(["--config", config_path if config_path else os.path.join(base_dir, "config", "vertex.json")])
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
        )
    except Exception as e:
        sys.stderr.write(f"[SSE Error] Launch failed: {e}\n")
        return response

    session = SessionContext(session_id, proc, response)
    sessions[session_id] = session
    print(f"[SSE] New session created: {session_id}")
    await session.send_event("endpoint", f"/messages?sessionId={session_id}")

    # Forward stderr in background
    async def log_stderr():
        while proc.stderr and not proc.stderr.at_eof():
            line = await proc.stderr.readline()
            if line:
                sys.stderr.write(f"[Server {session_id[:6]}] {line.decode('utf-8')}")
    asyncio.create_task(log_stderr())

    try:
        while not session.closed and proc.stdout and not proc.stdout.at_eof():
            line = await proc.stdout.readline()
            if not line:
                break
            decoded = line.decode("utf-8").strip()
            if decoded:
                print(f"[SSE Out] -> {decoded[:80]}")
                await session.send_event("message", decoded)
    except Exception as e:
        print(f"[SSE Exception] {e}")
    finally:
        print(f"[SSE] Session ended: {session_id}")
        sessions.pop(session_id, None)
        await session.close()
    return response

async def handle_messages(request: web.Request) -> web.Response:
    session_id = request.query.get("sessionId")
    if not session_id or session_id not in sessions:
        return web.Response(status=404, text=f"Session not found", headers={"Access-Control-Allow-Origin": "*"})
    session = sessions[session_id]
    body = await request.read()
    if not body:
        return web.Response(status=400, text="Empty body", headers={"Access-Control-Allow-Origin": "*"})
    try:
        if session.proc.stdin:
            session.proc.stdin.write(body + b"\n")
            await session.proc.stdin.drain()
        return web.Response(status=202, text="Accepted", headers={"Access-Control-Allow-Origin": "*"})
    except Exception as e:
        return web.Response(status=500, text=str(e), headers={"Access-Control-Allow-Origin": "*"})

async def handle_options(request: web.Request) -> web.Response:
    return web.Response(
        status=204,
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
    )

def create_app(config_path: Optional[str] = None) -> web.Application:
    app = web.Application()
    app["config_path"] = config_path
    app.router.add_get("/holy-nano", handle_sse)
    app.router.add_get("/sse", handle_sse)
    app.router.add_post("/messages", handle_messages)
    app.router.add_route("OPTIONS", "/{tail:.*}", handle_options)
    return app

def main():
    parser = argparse.ArgumentParser(description="Holy Nano MCP - SSE Server")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port (default: 4392)")
    parser.add_argument("--host", type=str, default=DEFAULT_HOST, help="Host (default: 127.0.0.1)")
    parser.add_argument("--config", type=str, default=None, help="Config file")
    args = parser.parse_args()
    print(f"==================================================")
    print(f" Holy Nano MCP SSE Server running on:")
    print(f" -> http://{args.host}:{args.port}/holy-nano")
    print(f"==================================================")
    app = create_app(args.config)
    web.run_app(app, host=args.host, port=args.port)

if __name__ == "__main__":
    main()
