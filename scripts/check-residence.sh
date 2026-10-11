#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RESIDENT_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$RESIDENT_TEST_TMP"' EXIT
swiftc -O Sources/InputStats/ResidentService.swift Sources/InputStats/AXFocusObserver.swift \
    Tests/ResidentCheck/main.swift -o "$RESIDENT_TEST_TMP/resident-check"
python3 scripts/check-residence.py InputStats.app "$RESIDENT_TEST_TMP/resident-check"
