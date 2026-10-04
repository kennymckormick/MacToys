#!/usr/bin/env python3
"""Mount and exercise a release using temporary data, no real app or SSH hosts."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import socketserver
import subprocess
import tempfile
import threading
from urllib.request import ProxyHandler, build_opener
from urllib.parse import urlsplit
import uuid

from release import machos, sha256


def run(*args, **kwargs):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=45, **kwargs)
    if result.returncode:
        raise RuntimeError("Command failed: {}\n{}{}".format(args[0], result.stdout, result.stderr))
    return result.stdout


def verify_bundle(app, arch):
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    binaries = list(machos(app))
    assert binaries, "No executable code in the app"
    for binary in binaries:
        run("/usr/bin/codesign", "--verify", "--strict", binary)
        assert run("/usr/bin/lipo", "-archs", binary).strip() == arch, "Wrong architecture: " + str(binary)
        identifiers = {line.strip() for line in run("/usr/bin/otool", "-D", binary).splitlines()[1:]}
        links = run("/usr/bin/otool", "-L", binary).splitlines()[1:]
        for line in links:
            dependency = line.strip().split(" (", 1)[0]
            if dependency in identifiers:
                continue  # LC_ID_DYLIB describes this library; it is not a load dependency.
            assert dependency.startswith(("@", "/usr/lib/", "/System/Library/")), "External library: " + dependency
    resources = app / "Contents/Resources"
    for name in ("NotesEditor/index.html", "Portman/portman/static/index.html", "Python/bin/python3", "Python-Licenses/LICENSE.cpython.txt"):
        assert (resources / name).is_file(), "Missing resource: " + name
    manifest = json.loads((resources / "distribution.json").read_text())
    assert manifest["architecture"] == arch and manifest["notarized"] is False
    return len(binaries)


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        data = bytearray()
        while True:
            part = self.request.recv(65536)
            if not part:
                break
            data.extend(part)
        self.request.sendall(data)


def exercise(app, temp):
    resources = app / "Contents/Resources"
    python = resources / "Python/bin/python3"
    cli = app / "Contents/MacOS/portman"
    poison = temp / "unusable-external-tools"
    poison.mkdir()
    for name in ("python", "python3", "portman", "node", "pip"):
        fake = poison / name
        fake.write_text("#!/bin/sh\necho 'External development tool used' >&2\nexit 99\n")
        fake.chmod(0o755)
    (poison / "sitecustomize.py").write_text("raise RuntimeError('External Python settings used')\n")
    environment = {
        "HOME": str(temp / "home"), "PATH": str(poison) + ":/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_US.UTF-8", "TMPDIR": str(temp), "PYTHONHOME": "/no-external-python",
        "PYTHONPATH": str(poison), "PORTMAN_HOME": str(temp / "portman-state"),
        "INPUTSTATS_TEST_HOME": str(temp / "app-state"),
    }
    (temp / "home").mkdir()
    reported = json.loads(run(python, "-I", "-B", "-c",
        "import json,sys; print(json.dumps({'executable':sys.executable,'prefix':sys.prefix,'isolated':sys.flags.isolated}))", env=environment))
    assert Path(reported["prefix"]).resolve() == (resources / "Python").resolve()
    assert reported["isolated"] == 1
    def portman(*args):
        return json.loads(run(cli, *args, "--json", env=environment))
    with socketserver.ThreadingTCPServer(("127.0.0.1", 0), Echo) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            gui = portman("gui", "--no-open")
            url = urlsplit(gui["url"])
            assert url.hostname == "127.0.0.1" and url.fragment.startswith("token=")
            with build_opener(ProxyHandler({})).open(gui["url"], timeout=10) as response:
                assert b"Portman" in response.read(), "Bundled GUI did not load"
            with socket.socket() as probe:
                probe.bind(("127.0.0.1", 0))
                forward = probe.getsockname()[1]
            mapping = portman("add", "packaged-echo", "--listen", str(forward),
                              "--target", "127.0.0.1:" + str(server.server_address[1]))
            assert mapping["status"] == "running", mapping
            payload = "MacToys 打包测试\n".encode() * 4096
            with socket.create_connection(("127.0.0.1", forward), 5) as connection:
                connection.settimeout(5)
                connection.sendall(payload)
                connection.shutdown(socket.SHUT_WR)
                result = bytearray()
                while True:
                    part = connection.recv(65536)
                    if not part:
                        break
                    result.extend(part)
                assert result == payload, "Packaged daemon changed TCP data"
            portman("stop", "packaged-echo")
            portman("start", "packaged-echo")
            assert len(portman("list")["mappings"]) == 1
            portman("remove", "packaged-echo")
            assert portman("list")["mappings"] == []
            # Actual worker bootstrap, using only the system SSH version command.
            with subprocess.Popen([str(python), "-I", "-B", str(resources / "Portman/portman/_entry.py"),
                                   "portman.ssh_worker", "/usr/bin/ssh", "-V"], env=environment,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as worker:
                assert worker.wait(timeout=10) == 0, worker.stderr.read().decode()
                assert b"OpenSSH" in worker.stderr.read()
        finally:
            with contextlib.suppress(Exception):
                portman("daemon", "stop")
            server.shutdown()
    # Runtime use must not change a signed resource or leave bytecode in the bundle.
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    assert not list((resources / "Portman").rglob("*.pyc"))

    # Only this temporary test copy receives a different identity. Permission
    # checks are read-only; the running user's installed app is never launched.
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] = "com.local.mactoys.releasecheck." + uuid.uuid4().hex
    info["CFBundleName"] = "MacToys Release Check"
    info_path.write_bytes(plistlib.dumps(info))
    run("/usr/bin/codesign", "--force", "--sign", "-", app)
    report = json.loads(run(app / "Contents/MacOS/InputStats", "--diagnostics", env=environment))
    assert Path(report["database"]) == temp / "app-state"
    assert report["bundledPortman"] and not report["monitorRunning"]
    assert report["todoStorageReady"] and report["goalStorageReady"] and report["notesStorageReady"]
    assert not report["scrollReversalRunning"] and not report["awakeEnabled"]
    return report["version"]


def check(dmg, arch):
    checksum = Path(str(dmg) + ".sha256").read_text().split()[0]
    assert sha256(dmg) == checksum, "DMG checksum mismatch"
    run("hdiutil", "verify", dmg)
    with tempfile.TemporaryDirectory(prefix="mactoys-release-check-") as name:
        temp = Path(name)
        mount = temp / "mounted"
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
        try:
            assert (mount / "Applications").is_symlink()
            assert os.readlink(mount / "Applications") == "/Applications"
            assert (mount / ".DS_Store").is_file() and (mount / "Read Me.html").is_file()
            app = temp / "Installed Apps With Spaces/MacToys.app"
            shutil.copytree(mount / "MacToys.app", app, symlinks=True)
        finally:
            run("hdiutil", "detach", mount)
        binaries = verify_bundle(app, arch)
        version = exercise(app, temp)
        print("Release verified: {} {} · {} signed Mach-O files · isolated app, offline resources, GUI, TCP, SSH worker, runtime relocation".format(version, arch, binaries))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dmg", type=Path)
    parser.add_argument("--arch", choices=("arm64", "x86_64"), required=True)
    args = parser.parse_args()
    check(args.dmg.resolve(), args.arch)
