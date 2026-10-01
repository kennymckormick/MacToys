#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SYNC_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$SYNC_TEST_TMP"' EXIT
swiftc -O -parse-as-library -I .build-mactoys/release/Modules \
    .build-mactoys/release/InputStatsCore.build/*.o .build-mactoys/release/InputStatsStorage.build/*.o \
    Sources/InputStats/Localization.swift Sources/InputStats/TodoStore.swift Sources/InputStats/GoalStore.swift Sources/InputStats/NotesStore.swift \
    Sources/InputStats/QuickPanelSettings.swift Sources/InputStats/ColorShortcut.swift \
    Sources/InputStats/BackupSnapshot.swift Sources/InputStats/LocalBackupStore.swift \
    Sources/InputStats/GitHubBackupClient.swift Sources/InputStats/SyncKeychain.swift Sources/InputStats/CloudSyncStore.swift \
    Tests/CloudSyncCheck/main.swift -lsqlite3 -framework Carbon -o "$SYNC_TEST_TMP/sync-check"
"$SYNC_TEST_TMP/sync-check"
