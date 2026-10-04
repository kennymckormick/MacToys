# Building MacToys

[English README](../README.md) · [中文 README](../README.zh-CN.md)

Releases include self-contained DMGs for Apple Silicon and Intel. These are ad-hoc signed, **not notarized**. See [installation](installing.md) for the first-open steps, or [release packaging](releasing.md) to build a DMG. The instructions below are for source builds.

## Requirements

- macOS 14 or later.
- Swift 5.9 or later, provided by Xcode or Command Line Tools.
- Python 3.9 or later for Portman. It uses the standard library and system OpenSSH; no third-party Python packages are required.

## Build and install

```sh
git clone https://github.com/kennymckormick/MacToys.git
cd MacToys
./build.sh --install
open /Applications/MacToys.app
```

Run `./build.sh` without `--install` to build `InputStats.app` in the repository. The build targets the current Mac's architecture.

The installed bundle remains at `/Applications/InputStats.app`, with `/Applications/MacToys.app` as a link. The executable name and bundle identifier remain `InputStats` and `com.local.inputstats` for compatibility with existing installations.

On first use, grant the installed app Accessibility and any requested Input Monitoring permission in System Settings → Privacy & Security, then restart it. The app does not reset system permissions.

## Signing local builds

The build script uses an existing `InputStats Self-Signed` certificate from the keychain, or an ad-hoc signature when that certificate is unavailable. To use your own existing code-signing identity:

```sh
SIGNING_IDENTITY='Your code-signing identity' ./build.sh --install
```

Keep the same identity across installed updates. Ad-hoc signatures do not provide a stable permission identity across builds. The installer stops if the new app's designated signing requirement differs from the installed app's. Certificates and private keys are not included in the repository.

This script is for local builds. `scripts/release.py` builds self-contained, ad-hoc signed downloads separately without touching the installed app. Developer ID distribution still needs hardened runtime, a secure timestamp, notarization, and a stapled ticket.

## Portman CLI

Portman source is included in the repository and app bundle. Source builds reuse an installed `portman` CLI when available; otherwise they launch the bundled module with an external Python interpreter. Release DMGs always use their bundled CLI and Python runtime; an existing Portman daemon and saved mappings are reused. No Python installation is needed for the DMG.

To install the CLI separately:

```sh
python3 -m pip install ./Modules/Portman
portman -h
```

See the [Portman CLI reference](../Modules/Portman/README.md) for commands and runtime behavior.

## Checks

Run from the repository root:

```sh
swift run -c release --scratch-path .build-mactoys SelfCheck
bash scripts/check-color-picker.sh
bash scripts/check-scroll-reversal.sh
bash scripts/check-keep-awake.sh
bash scripts/check-todos.sh
bash scripts/check-goals.sh
bash scripts/check-notes.sh
bash scripts/check-notes-editor.sh
bash scripts/check-cloud-sync.sh
bash scripts/check-localization.sh
bash scripts/check-release-setup.sh
(cd Modules/Portman && python3 -m unittest discover -s tests -v)
node --check Modules/Portman/portman/static/app.js
```

`python3 scripts/ui-fixture.py` creates a test app with a separate bundle ID, temporary database, and isolated Portman state. Real input monitoring is disabled by default.

The installer saves a backup before replacing an existing app. Backups are stored in `~/Library/Application Support/MacToys/Backups/`. Test output, app bundles, databases, and signing keys are excluded from version control.

## Notes editor

The offline editor bundle is committed in `Resources/NotesEditor`; a normal app build does not need npm or a network connection. To rebuild it after editing `Modules/NotesEditor`:

```sh
cd Modules/NotesEditor
npm ci --ignore-scripts
npm run build
```

Use Node.js 22, 24, or 26+. Dependencies are pinned in the lockfile. The build includes the licenses of all bundled dependencies in `THIRD-PARTY-NOTICES.txt`. `check-notes-editor.sh` runs the actual editor in an offscreen WebKit view with temporary notes; it does not send keyboard events to other apps.

## Source layout

| Directory | Contents |
| --- | --- |
| `Sources/InputStatsCore` | Counting, Fn state machine, time aggregation, color formats |
| `Sources/InputStatsStorage` | SQLite transactions, historical migration, failure recovery |
| `Sources/InputStats` | Native app, input monitoring, statistics, color picker, WebKit integration |
| `Modules/NotesEditor` | Offline Milkdown editor source and reproducible bundle build |
| `Modules/Portman` | Python CLI, daemon, web GUI, integration tests |
| `scripts` | Build, installation, icons, verification tools |

[Usage notes (中文)](usage.zh-CN.md) · [Architecture](architecture.md) · [Resource audit](performance.md) · [Verification](verification.md) · [Changelog](../CHANGELOG.md)
