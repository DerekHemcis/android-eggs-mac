#!/bin/zsh
# Assemble a distributable zip: prebuilt saver + scripts + (optional) video.
set -e
cd "$(dirname "$0")"
mkdir -p dist
rm -f "dist/Landroid-macOS.zip"
(cd . && zip -qry "dist/Landroid-macOS.zip" prebuilt scripts README.md \
   ${LANDROID_MOV:+"$LANDROID_MOV"})
echo "built dist/Landroid-macOS.zip"
