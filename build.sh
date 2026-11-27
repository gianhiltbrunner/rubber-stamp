#!/bin/zsh
# Builds "Rubber Stamp.app" into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/Rubber Stamp.app"
mkdir -p build
scripts/make-app.sh "$(swift build -c release --show-bin-path)/RubberStamp" "$APP" "$(git describe --tags --always 2>/dev/null || echo dev)"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x RubberStamp 2>/dev/null || true
  rm -rf "/Applications/Rubber Stamp.app"
  cp -R "$APP" /Applications/
  open "/Applications/Rubber Stamp.app"
  echo "Installed to /Applications and launched"
fi
