"""Run a bundled module without importing a user's site packages or PYTHONPATH."""
import runpy
import sys
from pathlib import Path

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("portman", "portman.ssh_worker"):
        raise SystemExit("Expected a Portman module")
    module = sys.argv.pop(1)
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    runpy.run_module(module, run_name="__main__", alter_sys=True)
