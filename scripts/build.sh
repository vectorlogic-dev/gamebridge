#!/usr/bin/env bash
# Build GameBridge into ./build/GameBridge.app instead of the deep DerivedData
# path Xcode uses by default. Pass `--run` to launch the fresh build.

set -euo pipefail

cd "$(dirname "$0")/.."

osascript -e 'tell application "GameBridge" to quit' 2>/dev/null || true
pkill -f "GameBridge.app/Contents/MacOS/GameBridge" 2>/dev/null || true

xcodebuild \
    -scheme GameBridge \
    -configuration Debug \
    -derivedDataPath build/dd \
    CONFIGURATION_BUILD_DIR="$(pwd)/build" \
    build

APP="$(pwd)/build/GameBridge.app"
echo
echo "Built: $APP"

if [[ "${1:-}" == "--run" ]]; then
    open "$APP"
fi
