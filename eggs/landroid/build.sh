#!/bin/zsh
# Build Landroid.saver (and the fullscreen runner) from src/.
set -e
cd "$(dirname "$0")"

SDK=$(xcrun --show-sdk-path)
OUT=dist/Landroid.saver/Contents
rm -rf dist/Landroid.saver
mkdir -p "$OUT/MacOS"

swiftc -O -module-name Landroid -emit-library -sdk "$SDK" \
  -framework ScreenSaver -framework AppKit -framework CoreVideo -framework QuartzCore \
  -Xlinker -bundle \
  -Xlinker -exported_symbols_list -Xlinker tools/exported_symbols.txt \
  src/LandroidSaver.swift src/wordlists.swift \
  -o "$OUT/MacOS/Landroid"

cp src/Info.plist "$OUT/Info.plist"
codesign --force --sign - --identifier com.dsh.landroid.saver --timestamp=none dist/Landroid.saver
echo "built dist/Landroid.saver"

# optional: standalone fullscreen runner
mkdir -p dist
if swiftc -O -sdk "$SDK" -framework ScreenSaver -framework AppKit \
    tools/runner/main.swift -o dist/LandroidPreview 2>/dev/null; then
  echo "built dist/LandroidPreview"
fi
