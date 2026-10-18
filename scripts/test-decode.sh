#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 -framework ScreenSaver Sources/Diagnostics.swift Sources/PlaybackCore.swift Sources/PhotoSession.swift Tests/Decode/main.swift -o build/decode-check
build/decode-check "$PWD/LocalPhotos/Formats"
