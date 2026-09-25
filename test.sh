#!/bin/sh
# Run the Swift test target. Command Line Tools ship Swift Testing at
# framework/dylib paths SwiftPM does not search by default, and no XCTest.
# Pass-through args go to `swift test` (e.g. ./test.sh --filter Timeline).
set -e
cd "$(dirname "$0")"
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
D=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec swift test -Xswiftc -F"$F" -Xlinker -F"$F" \
  -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$D" "$@"
