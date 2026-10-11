"""Exercise the real app/helper with temporary data and a temporary LaunchAgent."""
import contextlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True, timeout=20).stdout


def wait_for(fn, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = fn()
        if result:
            return result
        time.sleep(0.1)
    raise AssertionError("Timed out waiting for isolated resident test")


def alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


with tempfile.TemporaryDirectory(prefix="mactoys-resident-check-") as name:
    temp = Path(name)
    app = temp / "Apps With Spaces/MacToys Test.app"
    shutil.copytree(Path(sys.argv[1]).resolve(), app)
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] = "com.local.mactoys.residentcheck." + uuid.uuid4().hex
    info["CFBundleName"] = "MacToys Resident Check"
    info_path.write_bytes(plistlib.dumps(info))
    run("codesign", "--force", "--sign", "-", app)
    state = temp / "state"
    state.mkdir()
    sentinel = state / "unrelated-data.txt"
    sentinel.write_bytes(b"must be preserved")
    agent = temp / "test-agent.plist"
    print(run(sys.argv[2], app, state, agent).strip(), flush=True)
    config = plistlib.loads(agent.read_bytes())
    config["Label"] += ".test." + uuid.uuid4().hex
    config["EnvironmentVariables"] = {"INPUTSTATS_TEST_HOME": str(state)}
    agent.write_bytes(plistlib.dumps(config))
    target = "gui/{}".format(os.getuid())
    service = target + "/" + config["Label"]

    def pid():
        try:
            value = int((state / "app.pid").read_text())
            return value if alive(value) else None
        except (FileNotFoundError, ValueError):
            return None

    def helper_pid():
        match = re.search(r"\n\s*pid = (\d+)", run("launchctl", "print", service))
        return int(match[1]) if match else None

    known = set()
    try:
        run("launchctl", "bootstrap", target, agent)
        first = wait_for(pid); known.add(first)
        original_helper = wait_for(helper_pid)
        # Kill only the isolated helper; launchd must replace it and adopt the
        # existing app rather than launch a duplicate or kill the app's group.
        os.kill(original_helper, signal.SIGKILL)
        next_helper = wait_for(lambda: (p := helper_pid()) and p != original_helper and p)
        assert pid() == first
        print("Helper crash: launchd restored supervision without restarting the app", flush=True)
        started = time.monotonic()
        os.kill(first, signal.SIGKILL)
        second = wait_for(lambda: (p := pid()) and p != first and p); known.add(second)
        print("App crash: relaunched in {:.1f}s".format(time.monotonic() - started), flush=True)
        duplicate = subprocess.run(config["ProgramArguments"], capture_output=True, timeout=5)
        assert duplicate.returncode == 0 and pid() == second
        os.kill(second, signal.SIGTERM)
        third = wait_for(lambda: (p := pid()) and p != second and p); known.add(third)
        assert sentinel.read_bytes() == b"must be preserved"
        print("Normal exit: relaunched; duplicate helper rejected; data preserved", flush=True)
        run("launchctl", "bootout", service)
        time.sleep(1)
        assert pid() == third, "Disabling residence must not terminate the app"
        os.kill(third, signal.SIGTERM)
        wait_for(lambda: not alive(third))
        time.sleep(5)
        assert pid() is None, "Disabled service relaunched the app"
        print("Disabling residence: app stayed alive, then quit without relaunch", flush=True)
    finally:
        subprocess.run(["launchctl", "bootout", service], capture_output=True, timeout=10)
        current = pid()
        if current:
            known.add(current)
        for process in known:
            if alive(process):
                with contextlib.suppress(ProcessLookupError):
                    os.kill(process, signal.SIGTERM)
        for process in known:
            if alive(process):
                wait_for(lambda: not alive(process), timeout=10)
