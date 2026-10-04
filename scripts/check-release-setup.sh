#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RELEASE_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$RELEASE_TEST_TMP"' EXIT
swiftc -O -parse-as-library Sources/InputStats/Localization.swift Sources/InputStats/SetupChecklist.swift \
    Sources/InputStats/PortmanLaunch.swift Tests/ReleaseCheck/main.swift -o "$RELEASE_TEST_TMP/release-check"
mkdir -p output/verification
"$RELEASE_TEST_TMP/release-check" "$PWD/output/verification/setup.png"
