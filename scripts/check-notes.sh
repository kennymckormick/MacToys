#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
NOTES_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$NOTES_TEST_TMP"' EXIT
swiftc -O -parse-as-library Sources/InputStats/Localization.swift Sources/InputStats/NotesStore.swift Tests/NotesCheck/main.swift -o "$NOTES_TEST_TMP/notes-check"
"$NOTES_TEST_TMP/notes-check"
