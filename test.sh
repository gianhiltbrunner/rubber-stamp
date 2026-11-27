#!/bin/zsh
# Runs the tests. With Command Line Tools only (no Xcode), SwiftPM does not find the
# Swift Testing macro plugin on its own, so its folder is passed explicitly.
set -euo pipefail
cd "$(dirname "$0")"
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
  swift test "$@"
fi
