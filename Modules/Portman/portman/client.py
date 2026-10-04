import json
import os
import subprocess
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener

from .common import PortmanError, private_dir, read_json, python_command


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


def ensure(home):
    runtime = running(home)
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
        proc = subprocess.Popen(python_command("portman", "--home", str(home), "_serve"),
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
