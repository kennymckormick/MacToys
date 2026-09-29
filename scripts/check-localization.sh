#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
L10N_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$L10N_TEST_TMP"' EXIT
swiftc -O Sources/InputStats/Localization.swift Tests/LocalizationCheck/main.swift -o "$L10N_TEST_TMP/localization-check"
"$L10N_TEST_TMP/localization-check"
node Tests/LocalizationCheck/portman.cjs
