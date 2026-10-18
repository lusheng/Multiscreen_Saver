#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 Sources/PlaybackCore.swift Tests/Core/main.swift -o build/core-check
build/core-check
