# Install MacToys

**English** · [简体中文](installing.zh-CN.md)

Requires macOS 14 or later. Choose **arm64** for an Apple Silicon Mac (M1 or newer), or **x86_64** for an Intel Mac. Check Apple menu → About This Mac if unsure.

1. Download the matching DMG from [GitHub Releases](https://github.com/kennymckormick/MacToys/releases/latest).
2. Open it and drag **MacToys.app** to **Applications**. Eject the disk image.
3. Open MacToys from Applications. This release is **not notarized**. If macOS blocks it, after attempting to open it, go to **System Settings → Privacy & Security → Open Anyway**. Only approve a download you trust. Managed Macs may disallow this exception. [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)
4. The first launch opens Settings → Getting started. Input Stats and Scroll Reversal need **Accessibility** and any requested **Input Monitoring** permission. Enable MacToys in System Settings, then quit and reopen it. If the app is missing from the list, use **+** to add the installed copy.

Todos, Notes, Goals, Portman, and Keep Awake work without those permissions. The app never changes system security settings itself. Closing its window leaves the menu bar app running; use **Quit MacToys** to exit.

The app includes Python, Portman, and the offline Notes editor. Users do not need Xcode, Command Line Tools, Homebrew, Python, pip, Node.js, or Rosetta when using the correct architecture. SSH tunnels use macOS's OpenSSH and still need your hosts, keys, or login credentials.

## Update and data

Quit MacToys before replacing the app with a newer version. Your todos, notes, goals, and statistics stay in `~/Library/Application Support/InputStats`; replacing the app does not erase them. Private GitHub backups remain optional.

Ad-hoc signatures can change between releases, so macOS may ask you to grant permissions again after an update. These downloads are not Developer ID signed and do not have an Apple notarization ticket.

If you previously installed from source as `InputStats.app` with a `MacToys.app` symlink, keep using `./build.sh --install` with your original signing identity. Switching to a DMG is a separate migration: back up first, quit the old app, remove the old application copies, install the DMG, and grant permissions again. Keep the data folder. Do not run two installations against the same data.

## CLI and download verification

The included CLI is available without modifying your shell configuration:

```sh
/Applications/MacToys.app/Contents/MacOS/portman -h
```

Each release includes a SHA-256 file. Download it beside the DMG and run, for example:

```sh
shasum -a 256 -c MacToys-0.7.1-arm64-unnotarized.dmg.sha256
```

The expected result is `OK`. The accompanying JSON records the source commit, Python version, architecture, and signing status. Checksums detect download corruption; they do not replace Developer ID signing.
