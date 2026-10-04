# MacToys

**English** · [简体中文](README.zh-CN.md)

Todo lists, Markdown notes, long-term goals, input statistics, port forwarding, color picking, mouse wheel reversal, sleep prevention, and private GitHub backups for macOS 14+.

[Download for Apple Silicon](https://github.com/kennymckormick/MacToys/releases/download/v0.7.1/MacToys-0.7.1-arm64-unnotarized.dmg) · [Download for Intel](https://github.com/kennymckormick/MacToys/releases/download/v0.7.1/MacToys-0.7.1-x86_64-unnotarized.dmg)

Drag MacToys to Applications. Python and Portman are included; no development tools are needed. This release is **not notarized**: macOS may require **System Settings → Privacy & Security → Open Anyway** on first launch. [Installation and permissions](docs/installing.md)

## Menu bar

- Notes is pinned in the menu bar. Choose up to three more tabs from Todo, Goals, Stats, Colors, Scroll, and Awake in Settings → Quick Panel.
- Set which tab opens each time you click the menu bar icon. Todo is the default.
- Use English or Simplified Chinese, or follow the system language. Switch without restarting.

## Todo List

- Add, edit, complete, and delete tasks from the menu bar or main window.
- Expand completed tasks to restore them, or clear them together.
- Tasks are shared between both views and saved locally across restarts.

## Notes

- Edit Markdown as formatted text, with headings, bold, italic, lists, checkboxes, quotes, code blocks, links, and tables.
- Switch to Markdown source and export individual notes as `.md` files.
- Keep multiple notes with titles. Changes save locally as you type, in both the menu bar and main window.
- The editor runs offline. Remote images and embedded HTML do not load.

## Long-term Goals

- Keep a goal and its current status as two editable text fields.
- Add, update, and delete goals from the main window or an optional Goals tab in the menu bar.
- Goals persist until you delete them.

## Cloud Sync

- Manually back up tasks, notes, goals, input counts, saved colors, and preferences to a private GitHub repository.
- Restore the snapshot on another Mac. A local backup is saved before every restore; data is replaced, not merged.
- Authorize with a fine-grained access token stored in the macOS Keychain. No background polling.
- Portman rules, SSH keys, system permissions, login items, and active Keep Awake sessions stay local.

[Set up Cloud Sync](docs/cloud-sync.md)

## InputStats

- Count characters and words, with separate keyboard and dictation totals. Detect dictation through Fn or select the source manually.
- View hourly totals, a 7-day trend, and a yearly heatmap.
- Check today's counts from the menu bar. Charts refresh every five minutes.
- Export CSV or JSON. Store counts locally without saving the text you type.

## Portman

- Forward TCP ports locally or set up SSH local and reverse tunnels.
- Add, edit, start, and stop mappings through a GUI or CLI that share the same background service.
- Use existing SSH aliases and keys. Reconnect dropped tunnels automatically.
- Keep forwarding when the window closes.

## Color Picker

- Pick a screen color with the macOS magnifier. Use a custom global shortcut; the default is **Control + Option + Command + C**.
- Copy HEX, RGB, or HSL, with optional automatic copying after selection.
- Enter a HEX value or adjust a color in the system color panel.
- Keep recent colors and save favorites.

## Scroll Reversal

- Reverse vertical and horizontal mouse wheel scrolling independently.
- Keep trackpad scrolling and momentum unchanged. Continuous devices, including Magic Mouse, retain their original direction.
- Toggle from the menu bar; keep the setting when the window closes.

## Keep Awake

- Prevent idle sleep until switched off, or for 15 minutes to 4 hours.
- Optionally keep the display on while the Mac stays awake.
- Toggle from the menu bar; a dot beside the tool icon indicates an active session. Sessions end when MacToys quits.

[Build from source](docs/building.md) · [Usage notes (中文)](docs/usage.zh-CN.md)

## Support

[Buy me a coffee on Ko-fi](https://ko-fi.com/kennyutc)
