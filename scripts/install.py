"""Replace a verified local build, preserving the existing app identity and rollback zip."""
import datetime
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import time
import uuid

source, destination = map(Path, sys.argv[1:3])
installed = '--installed' in sys.argv[3:]
expected = 'com.local.inputstats'

def identity(app):
    with (app / 'Contents/Info.plist').open('rb') as f:
        return plistlib.load(f)['CFBundleIdentifier']

def requirement(app):
    result = subprocess.run(['codesign', '-d', '-r-', str(app)], capture_output=True, text=True, check=True)
    return next(line for line in (result.stdout + result.stderr).splitlines() if line.startswith('designated =>'))

assert identity(source) == expected, 'Unexpected source bundle'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
if destination.exists():
    assert identity(destination) == expected, 'Refusing to replace an unrelated app'
    if installed:
        assert requirement(source) == requirement(destination), 'Signing requirement changed; existing authorization may be lost'
if installed:
    alias = destination.with_name('MacToys.app')
    if alias.exists() or alias.is_symlink():
        assert alias.is_symlink() and alias.resolve() == destination.resolve(), 'MacToys.app is already used by another app'
    # Ask the owned GUI to quit through the standard macOS application lifecycle.
    # Launch Services apps can defer SIGTERM, so prefer NSRunningApplication.terminate().
    subprocess.run([str(source.resolve()/'Contents/MacOS/InputStats'), '--quit-running', str(destination.resolve())], check=True, timeout=10)
    # Wait only for this exact executable; no unrelated applications or Portman workers.
    processes = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True)
    for line in processes.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[1] == str(destination / 'Contents/MacOS/InputStats'):
            pid = int(fields[0])
            for _ in range(100):
                try: os.kill(pid, 0)
                except ProcessLookupError: break
                time.sleep(.1)
            else: raise RuntimeError('Existing app did not exit cleanly')
    backup = Path.home() / 'Library/Application Support/MacToys/Backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-install')
    backup.mkdir(parents=True)
    if destination.exists():
        subprocess.run(['ditto', '-c', '-k', '--keepParent', str(destination), str(backup/'InputStats.app.zip')], check=True)
# Copy/rename instead of mutating an executable's code-signed pages in place.
staged = destination.with_name('.' + destination.name + '-' + uuid.uuid4().hex)
shutil.copytree(source, staged)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(staged)], check=True)
previous = destination.with_name('.' + destination.name + '-previous-' + uuid.uuid4().hex)
if destination.exists(): destination.rename(previous)
try: staged.rename(destination)
except Exception:
    if previous.exists(): previous.rename(destination)
    raise
if previous.exists(): shutil.rmtree(previous)
if installed:
    if not alias.is_symlink(): alias.symlink_to(destination)
    print('Installed:', destination, '| Finder alias:', alias)
