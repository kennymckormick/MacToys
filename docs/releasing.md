# Build and publish a DMG

On macOS with Swift 5.9+ and Python 3.9+ available:

```sh
python3 scripts/release.py --arch arm64
python3 scripts/release.py --arch x86_64
python3 scripts/check-release.py dist/MacToys-0.7.1-arm64-unnotarized.dmg --arch arm64
python3 scripts/check-release.py dist/MacToys-0.7.1-x86_64-unnotarized.dmg --arch x86_64
```

Building can cross-compile. Executing checks needs the matching hardware, or Rosetta for Intel checks on Apple Silicon. CI validates each architecture on its native runner, including macOS 14 for arm64.

The builder uses `output/` for scratch files and writes DMGs, SHA-256 files, and build manifests to `dist/`. It does not install, quit, restart, or change the identity of an existing app. `build.sh` remains the separate source-development installer.

Python comes from [python-build-standalone](https://github.com/astral-sh/python-build-standalone). Runtime downloads and the build-only `ds-store`/`mac-alias` wheels are version-pinned and SHA-256 checked in `scripts/release-lock.json`. No global pip installation is performed. Dependency license texts are included in the app. When updating Python, update both architectures, checksums, and `Resources/Python-Licenses` from the matching full distribution.

A native CLI helper locates Python relative to its own executable. The app, daemon, and SSH worker use the same runtime, ignore user Python settings, and suppress bytecode writes in the signed app. Distribution builds use this helper before searching for external tools; source builds retain their existing fallback. Existing Portman daemon state remains in its original location.

## Validation

`check-release.py` mounts the DMG read-only, copies the app into a temporary directory with spaces, verifies all Mach-O signatures, architecture, and linked libraries, then exercises the bundled CLI, web UI, TCP forwarding, SSH worker bootstrap, and isolated native app diagnostics. External Python, Portman, pip, and Node commands are poisoned in PATH. Test state is temporary, and the native app gets a separate test identity. The installed user app and real SSH hosts are not touched.

The check validates dependencies and functional startup. It does not simulate a physical Mac with no prior TCC decisions or click through Gatekeeper. The downloads remain explicitly marked **unnotarized**. New users must follow the per-app first-open instructions.

## Publish

1. Update the app version and build number, download links, and `docs/releases/vVERSION.md`.
2. Commit the changes, then push the matching `vVERSION` tag.
3. The **Release DMG** workflow runs all application checks, builds on macOS 14 ARM and macOS 15 Intel runners, verifies both packages, and creates a GitHub Release with the two DMGs, checksums, and manifests. It checks that the tag, app version, and source commit match. No release is created if either architecture fails.

`workflow_dispatch` produces downloadable workflow artifacts without publishing a Release. Local `gh` authentication is not required for CI publication; the workflow uses GitHub's scoped token.

## Later: Developer ID

These packages are ad-hoc signed. They have no hardened runtime, secure timestamp, or notarization ticket. Do not label them notarized.

After Apple Developer enrollment is complete, add a separate Developer ID signing path for all nested code and the outer app, enable and test hardened runtime, submit with `notarytool`, and staple and validate the ticket. Review permissions and migration from previous signatures before updating existing users. Never commit certificates, private keys, or notarization credentials.
