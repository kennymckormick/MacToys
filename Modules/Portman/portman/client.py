import fcntl
from http.client import HTTPException
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener

from .common import PortmanError, atomic_json, private_dir, read_json, python_command, user_context_command, session_recovery_needed


class DaemonUnavailable(PortmanError):
    pass


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
    except (URLError, OSError, HTTPException) as e:
        raise DaemonUnavailable("Cannot reach Portman daemon: " + str(e)) from e
    except ValueError as e:
        raise PortmanError("Cannot reach Portman daemon: " + str(e)) from e


def read_current(home, runtime, path):
    """Retry a read once if another client replaced the daemon during recovery."""
    try:
        return runtime, request(runtime, path)
    except DaemonUnavailable:
        # Recovery deliberately does not block concurrent clients. Their first
        # read can therefore race the old daemon's exit. Wait only for a healthy
        # replacement; never restart a service or replay a mutation here.
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            replacement = running(home)
            if replacement and replacement != runtime:
                return replacement, request(replacement, path)
            time.sleep(0.1)
        raise


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
    return session_recovery_needed(mappings)


def recovery_on_cooldown(marker):
    # This is disposable coordination state, not user configuration. A damaged
    # marker or a clock moving backwards must not disable recovery permanently.
    try:
        previous = read_json(marker, {})
    except PortmanError:
        return False
    attempted = previous.get("attempted_at") if isinstance(previous, dict) else None
    if type(attempted) not in (int, float):
        return False
    try:
        return 0 <= time.time() - attempted < 300
    except OverflowError:
        return False


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
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            # Another client owns recovery; keep the GUI responsive.
            return runtime
        current = running(home)
        if current != runtime:
            return current
        try:
            if not needs_session_recovery(current):
                return current
        except PortmanError:
            return current
        marker = home / "recovery.json"
        if recovery_on_cooldown(marker):
            return current
        # -G with an empty config resolves the local account without making a
        # connection or invoking user SSH config. Only a healthy client repairs.
        try:
            probe = subprocess.run(user_context_command([
                "/usr/bin/ssh", "-G", "-F", os.devnull, "localhost"]),
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE, timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            return current
        if probe.returncode:
            return current
        atomic_json(marker, {"attempted_at": time.time()})
        # The server rechecks under its mutation lock and stops accepting new
        # starts before agreeing. A client-side snapshot alone has a race.
        # Old servers without this endpoint are left running; never fall back
        # to an unconditional shutdown after an error or an unknown outcome.
        try:
            result = request(current, "/api/recover-session", {}, timeout=2)
        except PortmanError:
            return current
        if result.get("stopping") is not True:
            return current
        deadline = time.monotonic() + 5
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
