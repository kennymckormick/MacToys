#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SCROLL_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$SCROLL_TEST_TMP"' EXIT
swiftc -O Sources/InputStats/MouseWheelReversal.swift Sources/InputStats/ScrollReversalStore.swift \
    Tests/ScrollReversalCheck/main.swift -o "$SCROLL_TEST_TMP/scroll-check"
"$SCROLL_TEST_TMP/scroll-check"
