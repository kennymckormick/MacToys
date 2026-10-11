#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --scratch-path .build-mactoys
COLOR_TEST_BUILD=$(swift build -c release --scratch-path .build-mactoys --show-bin-path)
COLOR_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$COLOR_TEST_TMP"' EXIT
if [ -f "$COLOR_TEST_BUILD/InputStatsCore.o" ]; then
    COLOR_TEST_MODULES="$COLOR_TEST_BUILD"
    COLOR_TEST_OBJECTS=("$COLOR_TEST_BUILD/InputStatsCore.o")
else
    COLOR_TEST_MODULES="$COLOR_TEST_BUILD/Modules"
    COLOR_TEST_OBJECTS=("$COLOR_TEST_BUILD"/InputStatsCore.build/*.swift.o)
fi
swiftc -O Sources/InputStats/Localization.swift -I "$COLOR_TEST_MODULES" \
    Sources/InputStats/ColorShortcut.swift Sources/InputStats/ColorPickerStore.swift \
    Tests/ColorPickerCheck/main.swift "${COLOR_TEST_OBJECTS[@]}" \
    -o "$COLOR_TEST_TMP/color-check"
"$COLOR_TEST_TMP/color-check"
