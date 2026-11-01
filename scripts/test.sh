#!/bin/bash
# End-to-end tests.
#   1. HookTests: the shipped hook and CLI scripts against a fake app socket (no app needed)
#   2. CrewNotchTests: those scripts against the real socket server and SessionStore,
#      hosted in the app, which stays inert under XCTest (safe while CrewNotch runs)
#
#   ./scripts/test.sh            both
#   ./scripts/test.sh hooks      only the Python tests
#   ./scripts/test.sh app        only the Xcode tests
set -euo pipefail
cd "$(dirname "$0")/.."

suite="${1:-all}"
case "$suite" in
    all|hooks|app) ;;
    *) echo "usage: $0 [all|hooks|app]" >&2; exit 2 ;;
esac

if [[ "$suite" != app ]]; then
    echo "==> Hook scripts (/usr/bin/python3, the interpreter CrewNotch installs hooks with)"
    PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s HookTests
fi

if [[ "$suite" != hooks ]]; then
    echo "==> App pipeline"
    # Own derived data, so the Debug app other workflows run is never replaced by a test build
    xcodebuild test \
        -scheme CrewNotch \
        -destination 'platform=macOS' \
        -derivedDataPath build/test \
        -enableCodeCoverage NO \
        -quiet
    echo "App pipeline tests passed"
fi
