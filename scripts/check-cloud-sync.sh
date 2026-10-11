#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SYNC_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$SYNC_TEST_TMP"' EXIT
SYNC_TEST_BUILD=$(swift build -c release --scratch-path .build-mactoys --show-bin-path)
if [ -f "$SYNC_TEST_BUILD/InputStatsCore.o" ]; then
    SYNC_TEST_MODULES="$SYNC_TEST_BUILD"
    SYNC_TEST_OBJECTS=("$SYNC_TEST_BUILD/InputStatsCore.o" "$SYNC_TEST_BUILD/InputStatsStorage.o")
else
    SYNC_TEST_MODULES="$SYNC_TEST_BUILD/Modules"
    SYNC_TEST_OBJECTS=("$SYNC_TEST_BUILD"/InputStatsCore.build/*.o "$SYNC_TEST_BUILD"/InputStatsStorage.build/*.o)
fi
swiftc -O -parse-as-library -I "$SYNC_TEST_MODULES" "${SYNC_TEST_OBJECTS[@]}" \
    Sources/InputStats/Localization.swift Sources/InputStats/TodoStore.swift Sources/InputStats/GoalStore.swift Sources/InputStats/NotesStore.swift \
    Sources/InputStats/QuickPanelSettings.swift Sources/InputStats/ColorShortcut.swift \
    Sources/InputStats/BackupSnapshot.swift Sources/InputStats/LocalBackupStore.swift \
    Sources/InputStats/GitHubBackupClient.swift Sources/InputStats/SyncKeychain.swift Sources/InputStats/DailyBackupSchedule.swift Sources/InputStats/CloudSyncStore.swift \
    Tests/CloudSyncCheck/main.swift -lsqlite3 -framework Carbon -o "$SYNC_TEST_TMP/sync-check"
"$SYNC_TEST_TMP/sync-check"
