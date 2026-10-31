#!/bin/zsh
# 安装 Landroid.saver 到 ~/Library/Screen Savers
set -e
cd "$(dirname "$0")"
SAVER=""
for c in "./Landroid.saver" "../prebuilt/Landroid.saver" "../dist/Landroid.saver"; do
  [ -d "$c" ] && SAVER="$(cd "$c" && pwd)" && break
done
if [ -z "$SAVER" ]; then
  echo "找不到 Landroid.saver，请先运行 ./build.sh"
  exit 1
fi
DEST="$HOME/Library/Screen Savers"
mkdir -p "$DEST"
rm -rf "$DEST/Landroid.saver"
cp -R "$SAVER" "$DEST/"
echo "已安装: $DEST/Landroid.saver"
defaults -currentHost write com.apple.screensaver moduleDict -dict moduleName -string "Landroid" path -string "$DEST/Landroid.saver" type -int 0
open "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension" 2>/dev/null || true
