#!/bin/zsh
cd "$(dirname "$0")"
MOV=""
for c in "./Landroid 锁屏.mov" "../dist/Landroid 锁屏.mov" "../Landroid 锁屏.mov"; do
  [ -f "$c" ] && MOV="$c" && break
done
if [ -z "$MOV" ]; then
  echo "找不到视频，请先运行 ./build-video.sh"
  exit 1
fi
/usr/bin/env python3 ./apply-lock.py "$MOV"
