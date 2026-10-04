#!/usr/bin/env python3
"""Build a self-contained, ad-hoc signed DMG; never install or stop the live app."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MACHO = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}


def run(*args, **kwargs):
    try:
        return subprocess.run([str(a) for a in args], check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        for output in (error.stdout, error.stderr):
            if output:
                print(output.decode(errors="replace") if isinstance(output, bytes) else output, file=sys.stderr)
        raise


def sha256(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def download(spec, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and sha256(destination) == spec["sha256"]:
        return destination
    with tempfile.TemporaryDirectory(dir=destination.parent) as tmp:
        staged = Path(tmp) / "download"
        run("/usr/bin/curl", "--fail", "--location", "--proto", "=https", "--proto-redir", "=https",
            "--retry", "3", "--silent", "--show-error", "--output", staged, spec["url"])
        if sha256(staged) != spec["sha256"]:
            raise RuntimeError("Checksum mismatch: " + spec["url"])
        staged.replace(destination)
    return destination


def extract_runtime(archive, destination):
    # Validate paths even though the upstream archive is pinned by SHA-256.
    with tarfile.open(archive, "r:gz") as source:
        for member in source.getmembers():
            name = PurePosixPath(member.name)
            if not name.parts or name.parts[0] != "python" or ".." in name.parts or name.is_absolute():
                raise RuntimeError("Unsafe runtime path: " + member.name)
            target = destination / Path(*name.parts)
            if not target.resolve().is_relative_to(destination.resolve()):
                raise RuntimeError("Runtime path escapes staging")
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as src, target.open("wb") as dst:
                    shutil.copyfileobj(src, dst)
                target.chmod(member.mode & 0o755)
            elif member.issym():
                link = (target.parent / member.linkname).resolve()
                if not link.is_relative_to(destination.resolve()):
                    raise RuntimeError("Runtime symlink escapes staging")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(member.linkname)
            else:
                raise RuntimeError("Unsupported runtime entry: " + member.name)
    return destination / "python"


def machos(directory):
    for path in sorted(directory.rglob("*")):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                if stream.read(4) in MACHO:
                    yield path


def layout(folder, lock, cache):
    # Build-time-only libraries: import verified wheels without a global pip install.
    for spec in lock["layoutTools"]:
        wheel = download(spec, cache / spec["name"])
        sys.path.insert(0, str(wheel))
    from ds_store import DSStore
    with DSStore.open(str(folder / ".DS_Store"), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["icvl"] = ("type", "icnv")
        store["."]["bwsp"] = {
            "WindowBounds": "{{180, 180}, {620, 380}}", "ShowToolbar": False,
            "ShowSidebar": False, "ShowStatusBar": False, "ShowPathbar": False,
            "ShowTabView": False, "ContainerShowSidebar": False,
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1, "backgroundType": 0, "arrangeBy": "none",
            "iconSize": 88.0, "textSize": 13.0, "labelOnBottom": True,
            "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
            "showItemInfo": False, "showIconPreview": True,
        }
        store["MacToys.app"]["Iloc"] = (150, 110)
        store["Applications"]["Iloc"] = (470, 110)
        store["Read Me.html"]["Iloc"] = (310, 255)


def build(arch, output):
    lock = json.loads((ROOT / "scripts/release-lock.json").read_text())
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    version = info["CFBundleShortVersionString"]
    output.mkdir(parents=True, exist_ok=True)
    cache = ROOT / "output/runtime-cache"
    archive = download(lock["runtimes"][arch], cache / (arch + ".tar.gz"))
    scratch = ROOT / "output/release-build" / arch
    triple = arch + "-apple-macosx14.0"
    print("Building MacToys", version, arch, flush=True)
    run("swift", "build", "-c", "release", "--product", "InputStats", "--triple", triple, "--scratch-path", scratch, cwd=ROOT)
    bin_path = Path(run("swift", "build", "-c", "release", "--triple", triple, "--scratch-path", scratch,
                        "--show-bin-path", cwd=ROOT, capture_output=True, text=True).stdout.strip())
    with tempfile.TemporaryDirectory(prefix=".mactoys-release-", dir=output) as temp:
        temp = Path(temp)
        folder = temp / "image"
        app = folder / "MacToys.app"
        contents = app / "Contents"
        resources = contents / "Resources"
        (contents / "MacOS").mkdir(parents=True)
        resources.mkdir()
        shutil.copy2(bin_path / "InputStats", contents / "MacOS/InputStats")
        shutil.copy2(ROOT / "Resources/Info.plist", contents / "Info.plist")
        for name in ("NotesEditor", "Python-Licenses"):
            shutil.copytree(ROOT / "Resources" / name, resources / name)
        shutil.copytree(ROOT / "Modules/Portman/portman", resources / "Portman/portman",
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store"))
        runtime = extract_runtime(archive, temp / "runtime")
        shutil.move(str(runtime), resources / "Python")
        # Remove only disposable bytecode caches included by upstream.
        for pycache in (resources / "Python").rglob("__pycache__"):
            shutil.rmtree(pycache)
        launcher = contents / "MacOS/portman"
        run("xcrun", "clang", "-arch", arch, "-mmacosx-version-min=14.0", "-Os", "-Wall", "-Wextra", "-Werror",
            ROOT / "scripts/portman-launcher.c", "-o", launcher)
        run("swift", ROOT / "scripts/make-icon.swift", temp / "AppIcon.iconset")
        run("iconutil", "-c", "icns", temp / "AppIcon.iconset", "-o", resources / "AppIcon.icns")
        manifest = {
            "version": version, "architecture": arch, "minimumMacOS": info["LSMinimumSystemVersion"],
            "pythonVersion": lock["pythonVersion"], "pythonRelease": lock["pythonRelease"],
            "pythonArchiveSHA256": lock["runtimes"][arch]["sha256"], "signing": "ad-hoc", "notarized": False,
            "commit": run("git", "rev-parse", "HEAD", cwd=ROOT, capture_output=True, text=True).stdout.strip(),
            "sourceModified": bool(run("git", "status", "--porcelain", cwd=ROOT, capture_output=True, text=True).stdout.strip()),
        }
        (resources / "distribution.json").write_text(json.dumps(manifest, indent=2) + "\n")
        for binary in machos(app):
            if binary == contents / "MacOS/InputStats":
                continue  # Sign the enclosing app last, after all nested code.
            run("codesign", "--force", "--sign", "-", "--timestamp=none", binary, capture_output=True)
        run("codesign", "--force", "--sign", "-", "--timestamp=none", app, capture_output=True)
        run("codesign", "--verify", "--deep", "--strict", app)
        (folder / "Applications").symlink_to("/Applications")
        shutil.copy2(ROOT / "Resources/Install.html", folder / "Read Me.html")
        layout(folder, lock, cache)
        filename = "MacToys-{}-{}-unnotarized.dmg".format(version, arch)
        staged = temp / filename
        run("hdiutil", "create", "-volname", "MacToys " + version, "-srcfolder", folder,
            "-fs", "HFS+", "-format", "UDZO", staged)
        run("hdiutil", "verify", staged)
        digest = sha256(staged)
        staged.replace(output / filename)
        (output / (filename + ".sha256")).write_text(digest + "  " + filename + "\n")
        manifest["dmgSHA256"] = digest
        (output / (filename + ".json")).write_text(json.dumps(manifest, indent=2) + "\n")
        print("Created:", output / filename, flush=True)
        return output / filename


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("arm64", "x86_64"), default=platform.machine())
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Build on macOS with Swift and Command Line Tools installed")
    build(args.arch, args.output.resolve())
