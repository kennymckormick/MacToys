#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --scratch-path .build-mactoys
COLOR_TEST_BUILD=$(swift build -c release --scratch-path .build-mactoys --show-bin-path)
COLOR_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$COLOR_TEST_TMP"' EXIT
swiftc -O Sources/InputStats/Localization.swift -I "$COLOR_TEST_BUILD/Modules" \
    Sources/InputStats/ColorShortcut.swift Sources/InputStats/ColorPickerStore.swift \
    Tests/ColorPickerCheck/main.swift "$COLOR_TEST_BUILD"/InputStatsCore.build/*.swift.o \
    -o "$COLOR_TEST_TMP/color-check"
"$COLOR_TEST_TMP/color-check"
