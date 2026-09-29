"""Tie the lifetime of one SSH process group to the daemon's stdin pipe.

EOF also cleans up after an abrupt daemon crash, without trusting saved PIDs.
"""
import os
import signal
import subprocess
import sys
import threading


def main():
    child = subprocess.Popen(sys.argv[1:], stdin=subprocess.DEVNULL, start_new_session=True)
    done = threading.Event()

    def stop(*_):
        done.set()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    def parent_pipe():
        try:
            while sys.stdin.buffer.read(1):
                pass
        finally:
            done.set()

    threading.Thread(target=parent_pipe, daemon=True).start()
    while child.poll() is None and not done.wait(0.2):
        pass
    # The unreaped child still owns its PID/group; never look up a saved PID.
    if child.returncode is None:
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    try:
        code = child.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        code = child.wait()
    return code if code >= 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
