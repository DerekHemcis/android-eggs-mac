#!/bin/zsh
# Build every egg under eggs/<name>/ (each has its own build.sh).
set -e
cd "$(dirname "$0")"
for d in eggs/*/; do
  [ -x "$d/build.sh" ] || continue
  echo "==> $d"
  (cd "$d" && ./build.sh)
done
echo "done"
