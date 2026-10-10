import fcntl
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener

from .common import PortmanError, atomic_json, private_dir, read_json, python_command, user_context_command


def request(runtime, path, data=None, timeout=35):
    port = runtime.get("port")
    if type(port) is not int or not 1 <= port <= 65535 or not isinstance(runtime.get("token"), str):
        raise PortmanError("Invalid runtime.json; daemon discovery failed")
    body = None if data is None else json.dumps(data).encode()
    req = Request("http://127.0.0.1:{}{}".format(port, path), data=body,
                  headers={"Authorization": "Bearer " + runtime["token"], "Content-Type": "application/json"})
    try:
        # Local control traffic must never be sent to HTTP_PROXY/HTTPS_PROXY.
        with build_opener(ProxyHandler({})).open(req, timeout=timeout) as res:
            return json.load(res)
    except HTTPError as e:
        try:
            message = json.load(e).get("error", str(e))
        except ValueError:
            message = str(e)
        raise PortmanError(message) from e
    except (URLError, OSError, ValueError) as e:
        raise PortmanError("Cannot reach Portman daemon: " + str(e)) from e


def running(home):
    runtime = read_json(home / "runtime.json")
    if runtime:
        try:
            health = request(runtime, "/api/health", timeout=1)
            if health.get("ok"):
                return runtime
        except PortmanError:
            pass
    return None


def needs_session_recovery(runtime):
    if sys.platform != "darwin":
        return False
    mappings = request(runtime, "/api/mappings", timeout=2).get("mappings", [])
    # Never interrupt an established forward or one that is still starting.
    if any(m.get("status") not in ("stopped", "retrying") for m in mappings):
        return False
    error = "No user exists for uid {}".format(os.getuid())
    return any(m.get("enabled") and m.get("mode") in ("ssh-local", "ssh-remote")
               and m.get("status") == "retrying" and m.get("error", "").strip() == error
               for m in mappings)


def recover_session(home, runtime):
    try:
        if not needs_session_recovery(runtime):
            return runtime
    except PortmanError:
        return runtime
    # Serialize repairs from concurrent CLI/GUI clients. The daemon's own lock
    # separately prevents duplicate replacements from starting.
    with (home / "recovery.lock").open("a+") as lock:
        os.fchmod(lock.fileno(), 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = running(home)
        if current != runtime or not needs_session_recovery(current):
            return current
        marker = home / "recovery.json"
        previous = read_json(marker, {})
        if time.time() - previous.get("attempted_at", 0) < 300:
            return current
        # -G with an empty config resolves the local account without making a
        # connection or invoking user SSH config. Only a healthy client repairs.
        try:
            probe = subprocess.run(user_context_command([
                "/usr/bin/ssh", "-G", "-F", os.devnull, "localhost"]),
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            return current
        if probe.returncode:
            return current
        atomic_json(marker, {"attempted_at": time.time()})
        request(current, "/api/shutdown", {})
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if not (home / "runtime.json").exists():
                return None
            replacement = running(home)
            if replacement and replacement != runtime:
                return replacement
            time.sleep(0.1)
        raise PortmanError("Portman session recovery is waiting for the old background service to stop; see daemon.log")


def ensure(home):
    runtime = running(home)
    if runtime:
        runtime = recover_session(home, runtime)
        if runtime:
            return runtime
    private_dir(home)
    path = home / "daemon.log"
    if path.exists() and path.stat().st_size > 1048576:
        path.replace(home / "daemon.log.1")
    # Do not depend on a developer's Python installation or environment.
    env = dict(os.environ, PORTMAN_HOME=str(home))
    source = str(Path(__file__).resolve().parent.parent)
    with path.open("ab") as log:
        proc = subprocess.Popen(user_context_command(python_command("portman", "--home", str(home), "_serve")),
                                stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                start_new_session=True, cwd=source, env=env)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        runtime = running(home)
        if runtime:
            return runtime
        if proc.poll() not in (None, 0):
            break
        time.sleep(0.1)
    details = "\n".join(path.read_text(errors="replace").splitlines()[-8:])
    raise PortmanError("Daemon did not start. See {}\n{}".format(path, details))
