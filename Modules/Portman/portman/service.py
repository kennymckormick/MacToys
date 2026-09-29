import asyncio
import contextlib
import fcntl
import hmac
import json
import os
import secrets
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from . import __version__
from .common import PortmanError, atomic_json, private_dir
from .manager import Manager, ssh_aliases


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False


class Handler(BaseHTTPRequestHandler):
    server_version = "Portman"

    def setup(self):
        super().setup()
        self.connection.settimeout(8)

    def log_message(self, *_):
        pass

    def reply(self, code, body, content_type="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
        self.end_headers()
        with contextlib.suppress(BrokenPipeError, ConnectionResetError):
            self.wfile.write(body)

    def guard(self, api=True):
        expected = "127.0.0.1:" + str(self.server.server_port)
        if self.headers.get("Host") != expected:
            self.reply(403, {"error": "Invalid Host"})
            return False
        origin = self.headers.get("Origin")
        if (origin and origin != "http://" + expected) or self.headers.get("Sec-Fetch-Site") == "cross-site":
            self.reply(403, {"error": "Cross-origin requests are not allowed"})
            return False
        token = self.headers.get("Authorization", "")
        if api and not hmac.compare_digest(token.encode(), ("Bearer " + self.server.token).encode()):
            self.reply(401, {"error": "Open the GUI with `portman gui` to authenticate"})
            return False
        return True

    def call(self, action, data):
        future = asyncio.run_coroutine_threadsafe(self.server.manager.dispatch(action, data), self.server.loop)
        # Do not cancel a committed mutation because a client disconnects/times out.
        return future.result(timeout=30)

    def do_GET(self):
        parsed = urlsplit(self.path)
        api = parsed.path.startswith("/api/")
        if not self.guard(api):
            return
        try:
            if parsed.path == "/api/health":
                self.reply(200, {"ok": True, "version": __version__, "pid": os.getpid(), "started_at": self.server.started_at})
            elif parsed.path == "/api/mappings":
                self.reply(200, self.call("list", {}))
            elif parsed.path == "/api/aliases":
                self.reply(200, {"aliases": ssh_aliases()})
            elif parsed.path == "/api/logs":
                name = parse_qs(parsed.query).get("name", [""])[0]
                self.reply(200, self.call("logs", {"name": name}))
            elif parsed.path in ("/", "/app.js", "/style.css", "/icon.svg"):
                filename, mime = {"/": ("index.html", "text/html; charset=utf-8"),
                                  "/app.js": ("app.js", "text/javascript; charset=utf-8"),
                                  "/style.css": ("style.css", "text/css; charset=utf-8"),
                                  "/icon.svg": ("icon.svg", "image/svg+xml")}[parsed.path]
                self.reply(200, (Path(__file__).parent / "static" / filename).read_bytes(), mime)
            else:
                self.reply(404, {"error": "Not found"})
        except PortmanError as e:
            self.reply(400, {"error": str(e)})
        except Exception as e:
            self.reply(500, {"error": str(e) or type(e).__name__})

    def do_POST(self):
        if not self.guard():
            return
        try:
            if self.headers.get_content_type() != "application/json":
                self.reply(415, {"error": "Use application/json"})
                return
            if self.headers.get("Transfer-Encoding"):
                raise PortmanError("Chunked requests are not supported")
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 65536:
                self.reply(413, {"error": "Request must be 1–65536 bytes"})
                return
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise PortmanError("Body must be a JSON object")
            action = urlsplit(self.path).path.removeprefix("/api/")
            if action == "shutdown":
                self.reply(200, {"stopping": True})
                self.server.loop.call_soon_threadsafe(self.server.stop_event.set)
            elif action in ("add", "edit", "start", "stop", "restart", "remove", "check"):
                self.reply(200, self.call(action, data))
            else:
                self.reply(404, {"error": "Unknown action"})
        except (PortmanError, ValueError) as e:
            self.reply(400, {"error": str(e)})
        except Exception as e:
            self.reply(500, {"error": str(e) or type(e).__name__})


async def serve(home):
    private_dir(home)
    with (home / "daemon.lock").open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        os.umask(0o077)
        manager = Manager(home)
        server = Server(("127.0.0.1", 0), Handler)
        server.manager = manager
        server.token = secrets.token_urlsafe(32)
        server.loop = asyncio.get_running_loop()
        server.stop_event = asyncio.Event()
        server.started_at = time.time()
        runtime = {"port": server.server_port, "token": server.token, "pid": os.getpid(), "version": __version__}
        for sig in (signal.SIGTERM, signal.SIGINT):
            server.loop.add_signal_handler(sig, server.stop_event.set)
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.15}, daemon=True)
        thread.start()
        atomic_json(home / "runtime.json", runtime)
        try:
            await manager.restore()
            await server.stop_event.wait()
        finally:
            await asyncio.to_thread(server.shutdown)
            await manager.close()
            server.server_close()
            with contextlib.suppress(FileNotFoundError):
                (home / "runtime.json").unlink()
        return 0
