#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
GOAL_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$GOAL_TEST_TMP"' EXIT
swiftc -O Sources/InputStats/Localization.swift Sources/InputStats/GoalStore.swift Tests/GoalCheck/main.swift -o "$GOAL_TEST_TMP/goal-check"
"$GOAL_TEST_TMP/goal-check"
