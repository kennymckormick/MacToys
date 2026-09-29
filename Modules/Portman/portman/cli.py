import argparse
import asyncio
import json
import os
import sys
import time
import webbrowser
from pathlib import Path
from urllib.parse import urlencode

from . import __version__
from .client import ensure, request, running
from .common import PortmanError, state_dir


def parser():
    p = argparse.ArgumentParser(prog="portman", description="Manage your own TCP and SSH port forwards; local GUI included.")
    p.add_argument("--version", action="version", version="Portman " + __version__)
    p.add_argument("--json", action="store_true", help="machine-readable JSON (accepted anywhere)")
    p.add_argument("--home", type=Path, help="isolated state directory (or PORTMAN_HOME)")
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("list", aliases=["ls"], help="list saved mappings and live state")
    sub.add_parser("hosts", help="list literal SSH config aliases")
    for command in ("add", "edit"):
        sp = sub.add_parser(command, help="create" if command == "add" else "update and apply a mapping")
        sp.add_argument("name")
        if command == "edit":
            sp.add_argument("--rename")
        sp.add_argument("--mode", choices=["tcp", "ssh-local", "ssh-remote"])
        sp.add_argument("--listen", required=command == "add", help="HOST:PORT, [IPv6]:PORT or PORT (loopback)")
        sp.add_argument("--target", required=command == "add", help="HOST:PORT or [IPv6]:PORT")
        sp.add_argument("--via", help="SSH alias, hostname, IP or USER@HOST")
        sp.add_argument("--ssh-port", type=int, help="override SSH connection port")
        if command == "add":
            sp.add_argument("--no-start", action="store_true", help="save without starting")
    for command in ("start", "stop", "restart", "remove", "logs", "check"):
        sp = sub.add_parser(command)
        sp.add_argument("name", help="mapping name or full ID")
        if command == "check":
            sp.add_argument("--http-path", help="also send HTTP GET through a local mapping, e.g. /health")
    sp = sub.add_parser("gui", help="open the authenticated local dashboard")
    sp.add_argument("--no-open", action="store_true", help="print the URL without opening a browser")
    sp = sub.add_parser("daemon", help="manage the background service")
    sp.add_argument("action", choices=["start", "status", "stop"])
    sub.add_parser("_serve", help=argparse.SUPPRESS)
    return p


def normalize_globals(argv):
    front, rest, i = [], [], 0
    while i < len(argv):
        value = argv[i]
        if value == "--json":
            front.append(value)
        elif value == "--home" and i + 1 < len(argv):
            front.extend(argv[i:i + 2])
            i += 1
        elif value.startswith("--home="):
            front.append(value)
        else:
            rest.append(value)
        i += 1
    return front + rest


def output(data, as_json):
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    elif "mappings" in data:
        if not data["mappings"]:
            print("No mappings. Create one with `portman add --help` or `portman gui`.")
            return
        rows = [[m["name"], m["status"], m["mode"], m["listen"], m["target"], m["via"] or "—"] for m in data["mappings"]]
        headers = ["NAME", "STATUS", "MODE", "LISTEN", "TARGET", "VIA"]
        widths = [max(len(str(row[i])) for row in [headers] + rows) for i in range(6)]
        for row in [headers] + rows:
            print("  ".join(str(cell).ljust(widths[i]) for i, cell in enumerate(row)))
        for m in data["mappings"]:
            if m["error"]:
                print("{}: {}".format(m["name"], m["error"]))
    elif "lines" in data:
        print("\n".join(data["lines"]) or "No logs yet.")
    elif "aliases" in data:
        print("\n".join(data["aliases"]) or "No literal SSH aliases found.")
    elif "url" in data:
        print(data["url"])
    elif "listen" in data:
        print("{}: {} | {} -> {}{}".format(data["name"], data["status"], data["listen"], data["target"],
              " via " + data["via"] if data["via"] else ""))
        if data.get("error"):
            print(data["error"])
    elif "message" in data:
        print(data["message"])
        if data.get("http_status"):
            print("HTTP status: " + str(data["http_status"]))
    else:
        print(json.dumps(data, ensure_ascii=False, indent=2))


def main(argv=None):
    args = parser().parse_args(normalize_globals(sys.argv[1:] if argv is None else argv))
    home = (args.home or state_dir()).expanduser().resolve()
    if args.command == "_serve":
        from .service import serve
        return asyncio.run(serve(home))
    try:
        if args.command == "daemon" and args.action in ("status", "stop"):
            runtime = running(home)
            if args.action == "status":
                result = request(runtime, "/api/health") if runtime else {"ok": False, "status": "stopped"}
            elif runtime:
                result = request(runtime, "/api/shutdown", {})
                deadline = time.monotonic() + 10
                # Wait for owned SSH workers and the state lock to be released.
                while (home / "runtime.json").exists() and time.monotonic() < deadline:
                    time.sleep(0.1)
                if (home / "runtime.json").exists():
                    raise PortmanError("Shutdown is still in progress; see daemon.log")
                result = {"status": "stopped", "saved_mappings_preserved": True}
            else:
                result = {"status": "stopped"}
        else:
            runtime = ensure(home)
            command = args.command
            if command in ("list", "ls"):
                result = request(runtime, "/api/mappings")
            elif command == "hosts":
                result = request(runtime, "/api/aliases")
            elif command == "gui":
                url = "http://127.0.0.1:{}/#token={}".format(runtime["port"], runtime["token"])
                if not args.no_open:
                    webbrowser.open(url)
                result = {"url": url}
            elif command == "daemon":
                result = request(runtime, "/api/health")
            elif command in ("add", "edit"):
                spec = {key: getattr(args, key) for key in ("mode", "listen", "target", "via", "ssh_port") if getattr(args, key) is not None}
                if command == "add":
                    spec["name"] = args.name
                    payload = {"spec": spec, "start": not args.no_start}
                else:
                    if args.rename:
                        spec["name"] = args.rename
                    if args.mode == "tcp":
                        spec.update(via="", ssh_port=None)
                    payload = {"name": args.name, "spec": spec}
                result = request(runtime, "/api/" + command, payload)
            elif command == "logs":
                result = request(runtime, "/api/logs?" + urlencode({"name": args.name}))
            else:
                payload = {"name": args.name}
                if command == "check" and args.http_path is not None:
                    payload["http_path"] = args.http_path
                result = request(runtime, "/api/" + command, payload)
        output(result, args.json)
        if args.command == "check" and not result.get("ok"):
            return 2
        if args.command in ("add", "start", "restart", "edit") and result.get("enabled") and result.get("status") != "running":
            return 2
        return 0
    except (PortmanError, OSError) as e:
        if args.json:
            print(json.dumps({"error": str(e)}, ensure_ascii=False))
        else:
            print("portman: " + str(e), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
