#!/bin/zsh
# Render the lock-screen video (180s, 2560x1440, HEVC) from the same simulation.
set -e
cd "$(dirname "$0")"
SDK=$(xcrun --show-sdk-path)
mkdir -p build dist
swiftc -O -sdk "$SDK" \
  -framework ScreenSaver -framework AppKit -framework AVFoundation -framework CoreVideo \
  tools/video/main.swift src/LandroidSaver.swift src/wordlists.swift -o build/render-video
./build/render-video "dist/Landroid 锁屏.mov"
echo "built dist/Landroid 锁屏.mov"
