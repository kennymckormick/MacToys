"""Tie the lifetime of one SSH process group to the daemon's stdin pipe.

EOF also cleans up after an abrupt daemon crash, without trusting saved PIDs.
"""
import os
import signal
import select
import subprocess
import sys


def main():
    child = subprocess.Popen(sys.argv[1:], stdin=subprocess.DEVNULL, start_new_session=True)
    stopping = False

    def stop(*_):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    # A daemon thread blocked in sys.stdin.buffer.read can abort Python during
    # shutdown when SSH exits before its parent closes the pipe. Watch the raw
    # descriptor in this loop instead; no buffered I/O lock survives shutdown.
    while child.poll() is None and not stopping:
        try:
            readable, _, _ = select.select([sys.stdin.fileno()], [], [], 0.2)
            if readable and not os.read(sys.stdin.fileno(), 4096):
                stopping = True
        except InterruptedError:
            continue
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
