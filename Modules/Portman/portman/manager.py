import asyncio
import contextlib
import copy
import datetime
import glob
import logging
import logging.handlers
import os
import shlex
import shutil
import socket
import sys
import tempfile
import time
import uuid
from pathlib import Path

from .common import PortmanError, address, atomic_json, endpoint, private_dir, read_json, validate_spec


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


class Mapping:
    def __init__(self, manager, record):
        self.manager, self.record = manager, record
        self.state, self.error = "stopped", ""
        self.task = self.proc = self.server = self.ctl = None
        self.ready = asyncio.Event()
        self.clients = set()
        self.connections = self.bytes_up = self.bytes_down = self.retries = 0
        self.started_at = self.last_check = None
        self.next_retry_at = None
        self.log_path = manager.home / "logs" / (record["id"] + ".log")
        self.logger = logging.Logger("portman." + record["id"])
        self.handler = logging.handlers.RotatingFileHandler(str(self.log_path), maxBytes=262144, backupCount=1)
        self.handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
        self.logger.addHandler(self.handler)

    @property
    def spec(self):
        return self.record["spec"]

    def log(self, message):
        self.logger.warning(str(message).replace("\x00", "")[:4000])

    def snapshot(self):
        return dict(self.record, **self.spec, status=self.state, error=self.error,
                    started_at=self.started_at, next_retry_at=self.next_retry_at,
                    retries=self.retries, active_connections=len(self.clients),
                    connections=self.connections, bytes_up=self.bytes_up,
                    bytes_down=self.bytes_down, last_check=self.last_check)

    async def start(self):
        if self.task and not self.task.done():
            return
        self.ready.clear()
        self.task = asyncio.create_task(self.run())
        # First setup result, including authentication/bind failure, is reviewable.
        with contextlib.suppress(asyncio.TimeoutError):
            await asyncio.wait_for(self.ready.wait(), timeout=14)

    async def stop(self):
        if self.task:
            self.task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.task
            self.task = None
        self.state, self.next_retry_at = "stopped", None
        self.log("Stopped")

    async def cleanup(self):
        if self.server:
            self.server.close()
            await self.server.wait_closed()
            self.server = None
        clients = list(self.clients)
        for task in clients:
            task.cancel()
        if clients:
            await asyncio.gather(*clients, return_exceptions=True)
        if self.proc:
            proc, self.proc = self.proc, None
            if proc.stdin:
                proc.stdin.close()
            try:
                await asyncio.wait_for(proc.wait(), 5)
            except asyncio.TimeoutError:
                with contextlib.suppress(ProcessLookupError):
                    proc.terminate()
                await proc.wait()
        if self.ctl:
            with contextlib.suppress(FileNotFoundError):
                Path(self.ctl).unlink()
            self.ctl = None

    async def run(self):
        delay = 1
        while True:
            self.state, self.next_retry_at = "starting", None
            active_time = None
            try:
                if self.spec["mode"] == "tcp":
                    lh, lp = endpoint(self.spec["listen"])
                    self.server = await asyncio.start_server(self.accept, lh, lp)
                else:
                    await self.start_ssh()
                active_time = time.monotonic()
                self.state, self.error, self.started_at = "running", "", now()
                self.log("Forward ready: {} -> {}{}".format(self.spec["listen"], self.spec["target"],
                         " via " + self.spec["via"] if self.spec["via"] else ""))
                self.ready.set()
                if self.spec["mode"] == "tcp":
                    await asyncio.Future()
                code = await self.proc.wait()
                raise PortmanError("SSH connection exited ({}); see logs".format(code))
            except asyncio.CancelledError:
                raise
            except Exception as e:
                self.error = str(e)
                self.log("Error: " + self.error)
                self.ready.set()
            finally:
                await self.cleanup()
            if active_time and time.monotonic() - active_time > 60:
                delay = 1
            self.retries += 1
            self.state = "retrying"
            self.next_retry_at = time.time() + delay
            await asyncio.sleep(delay)
            delay = min(delay * 2, 30)

    def accept(self, reader, writer):
        task = asyncio.create_task(self.proxy(reader, writer))
        self.clients.add(task)
        task.add_done_callback(self.clients.discard)

    async def proxy(self, reader, writer):
        upstream = None
        pumps = []
        try:
            th, tp = endpoint(self.spec["target"])
            remote, upstream = await asyncio.wait_for(asyncio.open_connection(th, tp), 10)
            self.connections += 1

            async def pump(src, dst, up):
                while True:
                    data = await src.read(65536)
                    if not data:
                        if dst.can_write_eof():
                            dst.write_eof()
                        return
                    dst.write(data)
                    await dst.drain()
                    if up:
                        self.bytes_up += len(data)
                    else:
                        self.bytes_down += len(data)

            pumps = [asyncio.create_task(pump(reader, upstream, True)),
                     asyncio.create_task(pump(remote, writer, False))]
            await asyncio.gather(*pumps)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            self.log("Target connection error: " + str(e))
        finally:
            for task in pumps:
                task.cancel()
            if pumps:
                await asyncio.gather(*pumps, return_exceptions=True)
            for stream in (writer, upstream):
                if stream:
                    stream.close()
                    with contextlib.suppress(Exception):
                        await asyncio.wait_for(stream.wait_closed(), 1)

    async def ssh_output(self, reader, lines):
        while True:
            data = await reader.readline()
            if not data:
                return
            msg = data.decode(errors="replace").strip()
            if msg:
                lines.append(msg)
                del lines[:-8]
                self.log(msg)

    async def control(self, *args):
        cmd = [self.manager.ssh, "-F", os.devnull, "-S", self.ctl, *args, "portman-control"]
        proc = await asyncio.create_subprocess_exec(*cmd, stdout=asyncio.subprocess.PIPE,
                                                    stderr=asyncio.subprocess.PIPE)
        try:
            out, err = await asyncio.wait_for(proc.communicate(), 5)
        except (asyncio.CancelledError, asyncio.TimeoutError):
            with contextlib.suppress(ProcessLookupError):
                proc.kill()
            await proc.wait()
            raise
        if proc.returncode:
            raise PortmanError(err.decode(errors="replace").strip() or "SSH control request failed")
        return out.decode(errors="replace")

    async def start_ssh(self):
        if not self.manager.ssh:
            raise PortmanError("OpenSSH client was not found")
        s = self.spec
        self.ctl = str(self.manager.sockets / (self.record["id"][:8] + ".sock"))
        # The private master inherits authentication/ProxyJump but no existing forwards.
        args = [self.manager.ssh, "-M", "-N", "-T", "-S", self.ctl]
        for option in ("ClearAllForwardings=yes", "ControlPersist=no", "ControlMaster=yes",
                       "ForkAfterAuthentication=no", "BatchMode=yes", "StrictHostKeyChecking=yes",
                       "ConnectTimeout=10", "ConnectionAttempts=1", "ServerAliveInterval=15",
                       "ServerAliveCountMax=3", "ExitOnForwardFailure=yes", "PermitLocalCommand=no",
                       "ForwardAgent=no", "ForwardX11=no", "RemoteCommand=none", "LogLevel=ERROR"):
            args += ["-o", option]
        if s["ssh_port"]:
            args += ["-p", str(s["ssh_port"])]
        args += ["--", s["via"]]
        self.proc = await asyncio.create_subprocess_exec(
            sys.executable, "-m", "portman.ssh_worker", *args,
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE, start_new_session=True)
        lines = []
        output_task = asyncio.create_task(self.ssh_output(self.proc.stderr, lines))
        # Consume stderr throughout the session; shutdown waits for EOF in cleanup.
        output_task.add_done_callback(lambda t: t.exception() if not t.cancelled() else None)
        deadline = time.monotonic() + 12
        while not Path(self.ctl).exists():
            if self.proc.returncode is not None:
                await output_task
                raise PortmanError("; ".join(lines) or "SSH authentication/connection failed")
            if time.monotonic() > deadline:
                raise PortmanError("SSH startup timed out; check host, key/agent and logs")
            await asyncio.sleep(0.08)
        lh, lp = endpoint(s["listen"])
        th, tp = endpoint(s["target"])
        spec = address(lh, lp) + ":" + address(th, tp)
        await self.control("-O", "forward", "-L" if s["mode"] == "ssh-local" else "-R", spec)
        if self.proc.returncode is not None:
            raise PortmanError("SSH exited while creating the forwarding")


class Manager:
    def __init__(self, home):
        self.home = private_dir(home)
        private_dir(home / "logs")
        self.lock = asyncio.Lock()
        self.ssh = shutil.which("ssh")
        # Short Unix socket paths work even with a long PORTMAN_HOME on macOS.
        self.sockets = Path(tempfile.mkdtemp(prefix="portman-", dir="/tmp"))
        self.items = {}
        data = read_json(home / "mappings.json", {"version": 1, "mappings": []})
        if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("mappings"), list):
            raise PortmanError("Unsupported or invalid mappings.json; original file has been preserved")
        names = set()
        for record in data["mappings"]:
            try:
                if str(uuid.UUID(record["id"])) != record["id"] or record["id"] in self.items:
                    raise ValueError("Invalid/duplicate mapping ID")
                record["spec"] = validate_spec(record["spec"])
                if record["spec"]["name"] in names or type(record["enabled"]) is not bool:
                    raise ValueError("Duplicate name or invalid enabled flag")
                names.add(record["spec"]["name"])
                self.items[record["id"]] = Mapping(self, record)
            except (KeyError, TypeError, ValueError) as e:
                raise PortmanError("Invalid saved mapping: " + str(e)) from e

    def save(self):
        atomic_json(self.home / "mappings.json", {"version": 1, "mappings": [m.record for m in self.items.values()]})

    def get(self, key):
        found = [m for m in self.items.values() if m.record["id"] == key or m.spec["name"] == key]
        if not found:
            raise PortmanError("Mapping not found: " + str(key))
        return found[0]

    def conflict(self, spec, skip=None):
        for m in self.items.values():
            if m is skip:
                continue
            if m.spec["name"] == spec["name"]:
                raise PortmanError("Name already exists: " + spec["name"])
            a, b = m.spec, spec
            remote_a, remote_b = a["mode"] == "ssh-remote", b["mode"] == "ssh-remote"
            same_side = remote_a == remote_b and (not remote_a or (a["via"], a["ssh_port"]) == (b["via"], b["ssh_port"]))
            if same_side and a["listen"] == b["listen"]:
                raise PortmanError("Listen address already configured by " + a["name"])

    async def restore(self):
        for m in self.items.values():
            if m.record["enabled"]:
                m.task = asyncio.create_task(m.run())

    async def close(self):
        await asyncio.gather(*(m.stop() for m in self.items.values()))
        for m in self.items.values():
            m.handler.close()
        shutil.rmtree(self.sockets, ignore_errors=True)

    async def dispatch(self, action, data):
        if action == "list":
            return {"mappings": [m.snapshot() for m in self.items.values()]}
        if action == "logs":
            m = self.get(data.get("name"))
            lines = m.log_path.read_text(errors="replace").splitlines()[-200:]
            return {"name": m.spec["name"], "lines": lines}
        if action == "check":
            return await self.check(self.get(data.get("name")), data.get("http_path"))
        async with self.lock:
            if action == "add":
                spec = validate_spec(data.get("spec"))
                for m in self.items.values():
                    if m.spec == spec:
                        return dict(m.snapshot(), reused=True)
                self.conflict(spec)
                record = dict(id=str(uuid.uuid4()), spec=spec, enabled=data.get("start", True), created_at=now(), updated_at=now())
                if type(record["enabled"]) is not bool:
                    raise PortmanError("start must be true or false")
                m = Mapping(self, record)
                self.items[record["id"]] = m
                try:
                    self.save()
                except Exception:
                    del self.items[record["id"]]
                    m.handler.close()
                    raise
                if record["enabled"]:
                    await m.start()
                return m.snapshot()
            m = self.get(data.get("name"))
            old = copy.deepcopy(m.record)
            if action == "edit":
                patch = data.get("spec", {})
                if not isinstance(patch, dict):
                    raise PortmanError("spec must be an object")
                spec = validate_spec(dict(m.spec, **patch))
                self.conflict(spec, m)
                m.record["spec"] = spec
            elif action in ("start", "stop", "restart"):
                m.record["enabled"] = action != "stop"
            elif action == "remove":
                del self.items[m.record["id"]]
            else:
                raise PortmanError("Unknown action: " + action)
            m.record["updated_at"] = now()
            try:
                self.save()
            except Exception:
                m.record = old
                self.items[old["id"]] = m
                raise
            if action != "start":
                await m.stop()
            if action != "remove" and m.record["enabled"]:
                await m.start()
            if action == "remove":
                m.handler.close()
                return {"removed": old["spec"]["name"]}
            return m.snapshot()

    async def check(self, m, http_path=None):
        s = dict(m.spec)
        if http_path is not None and (not isinstance(http_path, str) or not http_path.startswith("/")
                                     or any(ord(c) < 32 or ord(c) > 126 for c in http_path)):
            raise PortmanError("HTTP path must start with / and contain URL-encoded printable characters")
        result = {"checked_at": now(), "status": m.state, "listener_tcp": None,
                  "target_tcp": None, "http_status": None, "ok": False}

        async def connect(ep):
            h, p = endpoint(ep)
            if h == "0.0.0.0":
                h = "127.0.0.1"
            elif h == "::":
                h = "::1"
            return await asyncio.wait_for(asyncio.open_connection(h, p), 4)

        async def probe(ep):
            _, w = await connect(ep)
            w.close()
            with contextlib.suppress(Exception):
                await w.wait_closed()

        try:
            if m.state != "running":
                raise PortmanError("Forward is not running: " + (m.error or m.state))
            if s["mode"] == "ssh-remote":
                await m.control("-O", "check")
                await probe(s["target"])
                result["target_tcp"] = True
                result["message"] = "SSH control and local target reachable; remote listener and full path not verified"
                if http_path is not None:
                    raise PortmanError("HTTP path check for reverse forwarding must run on the SSH server")
            else:
                await probe(s["listen"])
                result["listener_tcp"] = True
                if s["mode"] == "tcp":
                    await probe(s["target"])
                    result["target_tcp"] = True
                    result["message"] = "Listener and target TCP reachable; application response not verified"
                else:
                    await m.control("-O", "check")
                    result["message"] = "Listener and SSH control reachable; target service not verified"
                if http_path is not None:
                    reader, writer = await connect(s["listen"])
                    try:
                        request = "GET {} HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n\r\n".format(http_path, s["target"])
                        writer.write(request.encode("ascii"))
                        await writer.drain()
                        line = (await asyncio.wait_for(reader.readline(), 5)).decode("ascii", errors="replace")
                        parts = line.split()
                        if len(parts) < 2 or not parts[0].startswith("HTTP/") or not parts[1].isdigit():
                            raise PortmanError("No valid HTTP response through the mapping")
                        result["http_status"] = int(parts[1])
                        result["target_tcp"] = True
                        result["message"] = "HTTP response received through mapping (application status is reported separately)"
                    finally:
                        writer.close()
                        with contextlib.suppress(Exception):
                            await writer.wait_closed()
            result["ok"] = True
        except Exception as e:
            result["message"] = str(e) or type(e).__name__
        m.last_check = result
        return result


def ssh_aliases():
    """Read literal Host entries (including Include); never execute Match commands."""
    aliases, seen = set(), set()

    def visit(path, depth=0):
        path = Path(path).expanduser()
        if depth > 10 or str(path) in seen:
            return
        seen.add(str(path))
        try:
            lines = path.read_text().splitlines()
        except OSError:
            return
        for line in lines:
            try:
                parts = shlex.split(line, comments=True)
            except ValueError:
                continue
            if not parts:
                continue
            # OpenSSH accepts both `Host x` and `Host=x`.
            if "=" in parts[0]:
                key, value = parts[0].split("=", 1)
                parts = [key, value] + parts[1:]
            key = parts[0].lower()
            if key == "host":
                aliases.update(v for v in parts[1:] if not any(c in v for c in "*?!"))
            elif key == "include":
                for pattern in parts[1:]:
                    pattern = os.path.expanduser(pattern)
                    if not os.path.isabs(pattern):
                        pattern = str(Path.home() / ".ssh" / pattern)
                    for included in glob.glob(pattern):
                        visit(included, depth + 1)

    visit(Path.home() / ".ssh/config")
    return sorted(aliases, key=str.lower)
