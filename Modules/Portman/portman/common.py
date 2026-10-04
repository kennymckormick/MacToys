import ipaddress
import json
import os
import re
import tempfile
import sys
from pathlib import Path


class PortmanError(Exception):
    pass


def python_command(module, *args):
    # Every descendant uses the same relocatable runtime, including SSH workers.
    # -I ignores user Python settings; -B keeps the signed app read-only.
    return [sys.executable, "-I", "-B", str(Path(__file__).with_name("_entry.py")), module, *args]


def state_dir():
    return Path(os.environ.get("PORTMAN_HOME", "~/.local/state/portman")).expanduser().resolve()


def private_dir(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    return path


def atomic_json(path, value):
    fd, name = tempfile.mkstemp(prefix=".write-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(value, f, ensure_ascii=False, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default
    except (ValueError, OSError) as e:
        raise PortmanError("Cannot read {}: {}".format(path, e)) from e


def host(value):
    if not isinstance(value, str) or not value or len(value) > 253:
        raise PortmanError("Host must be an IP address or hostname")
    value = value.strip("[]")
    if any(c.isspace() for c in value) or value.startswith("-"):
        raise PortmanError("Invalid host: " + value)
    try:
        ipaddress.ip_address(value)
    except ValueError:
        if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", value):
            raise PortmanError("Invalid IP address or hostname: " + value)
    return value


def endpoint(value, default_host=None):
    if not isinstance(value, str):
        raise PortmanError("Endpoint must be HOST:PORT or [IPv6]:PORT")
    if value.isdigit() and default_host:
        h, p = default_host, value
    elif value.startswith("[") and "]:" in value:
        h, p = value[1:].split("]:", 1)
    elif value.count(":") == 1:
        h, p = value.rsplit(":", 1)
    else:
        raise PortmanError("Use HOST:PORT, [IPv6]:PORT, or a listen port")
    h = host(h)
    if not p.isdigit() or not 1 <= int(p) <= 65535:
        raise PortmanError("Port must be between 1 and 65535")
    return h, int(p)


def address(h, p):
    return "[{}]:{}".format(h, p) if ":" in h else "{}:{}".format(h, p)


def validate_spec(raw):
    if not isinstance(raw, dict):
        raise PortmanError("Mapping must be an object")
    allowed = {"name", "mode", "listen", "target", "via", "ssh_port"}
    extra = set(raw) - allowed
    if extra:
        raise PortmanError("Unknown fields: " + ", ".join(sorted(extra)))
    name = raw.get("name", "")
    if not isinstance(name, str) or not re.fullmatch(r"[\w][\w .-]{0,63}", name):
        raise PortmanError("Name: 1–64 letters, digits, spaces, dots, hyphens or underscores")
    mode = raw.get("mode") or ("ssh-local" if raw.get("via") else "tcp")
    if mode not in ("tcp", "ssh-local", "ssh-remote"):
        raise PortmanError("Mode must be tcp, ssh-local or ssh-remote")
    lh, lp = endpoint(raw.get("listen"), "127.0.0.1")
    th, tp = endpoint(raw.get("target"))
    via = raw.get("via") or ""
    port = raw.get("ssh_port")
    if mode == "tcp":
        if via or port is not None:
            raise PortmanError("TCP mode does not use an SSH host/port")
    else:
        if not isinstance(via, str) or not via:
            raise PortmanError("SSH mode requires --via HOST or USER@HOST")
        if "@" in via:
            user, vh = via.rsplit("@", 1)
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", user):
                raise PortmanError("Invalid SSH user")
        else:
            vh = via
        host(vh)
        if port is not None and (type(port) is not int or not 1 <= port <= 65535):
            raise PortmanError("SSH port must be between 1 and 65535")
    return dict(name=name, mode=mode, listen=address(lh, lp), target=address(th, tp),
                via=via, ssh_port=port)
