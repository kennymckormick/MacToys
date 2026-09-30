#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TODO_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TODO_TEST_TMP"' EXIT
swiftc -O Sources/InputStats/Localization.swift Sources/InputStats/TodoStore.swift Sources/InputStats/QuickPanelSettings.swift \
    Tests/TodoCheck/main.swift -o "$TODO_TEST_TMP/todo-check"
"$TODO_TEST_TMP/todo-check"
