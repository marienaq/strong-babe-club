#!/usr/bin/env bash
# Runs the WorkoutCore unit tests.
#   - With full Xcode (XCTest available): `swift test`.
#   - With Command Line Tools only: builds the same test sources as an
#     executable against the bundled XCTest-compatible shim and runs it.
# Usage: scripts/test-core.sh [--local] [filter]
set -euo pipefail
cd "$(dirname "$0")/../Packages/WorkoutCore"

mode="auto"
if [[ "${1:-}" == "--local" ]]; then mode="local"; shift; fi
filter="${1:-}"

has_xctest() {
  xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1 &&
    [[ -d "$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/Library/Frameworks/XCTest.framework" ]]
}

if [[ "$mode" == "auto" ]] && has_xctest; then
  echo "==> XCTest found: swift test"
  if [[ -n "$filter" ]]; then swift test --filter "$filter"; else swift test; fi
else
  echo "==> No XCTest (Command Line Tools): running tests via the local shim runner"
  WORKOUTCORE_LOCAL_TESTS=1 swift build --product WorkoutCoreTestRunner
  WORKOUTCORE_LOCAL_TESTS=1 swift run --skip-build WorkoutCoreTestRunner $filter
fi
