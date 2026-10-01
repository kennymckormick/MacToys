#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
EDITOR_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$EDITOR_TEST_TMP"' EXIT
swiftc -O -parse-as-library Sources/InputStats/Localization.swift Sources/InputStats/NotesStore.swift Sources/InputStats/NotesEditor.swift Tests/NotesEditorCheck/main.swift -o "$EDITOR_TEST_TMP/editor-check"
mkdir -p output/verification
"$EDITOR_TEST_TMP/editor-check" "$PWD/Resources/NotesEditor" "$PWD/output/verification/notes-editor.png"
