#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 -framework ScreenSaver -framework AppKit -framework QuartzCore Sources/*.swift Tests/main.swift -o build/lifecycle-check
build/lifecycle-check
