#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project MultiscreenSaver.xcodeproj -target MultiscreenSaver -configuration Debug CONFIGURATION_BUILD_DIR="$PWD/build" build "$@"
