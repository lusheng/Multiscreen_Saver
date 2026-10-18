#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -O -swift-version 5 Sources/PlaybackCore.swift Sources/KenBurnsGeometry.swift Sources/PhotoRenderer.swift Tests/Render/main.swift -o build/render-check
build/render-check
