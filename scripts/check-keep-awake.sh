#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
AWAKE_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$AWAKE_TEST_TMP"' EXIT
swiftc -O Sources/InputStats/SystemAwakeAssertion.swift Sources/InputStats/KeepAwakeStore.swift \
    Tests/KeepAwakeCheck/main.swift -o "$AWAKE_TEST_TMP/awake-check"
"$AWAKE_TEST_TMP/awake-check"
