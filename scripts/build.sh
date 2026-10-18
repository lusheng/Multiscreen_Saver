#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project MultiscreenSaver.xcodeproj -target MultiscreenSaver -configuration "${CONFIGURATION:-Release}" CONFIGURATION_BUILD_DIR="$PWD/build" build "$@"
