#!/bin/zsh
# Rebuild NeewerLight.app. Command Line Tools only — no Xcode needed.
set -e
cd "$(dirname "$0")"
CACHE="${TMPDIR:-/tmp}/neewerlight-modcache"
mkdir -p "$CACHE" NeewerLight.app/Contents/MacOS
swiftc -O -module-cache-path "$CACHE" \
  -target arm64-apple-macos13.0 \
  -o NeewerLight.app/Contents/MacOS/NeewerLight \
  Sources/NeewerLight/*.swift
codesign --force --sign - NeewerLight.app
echo "Built NeewerLight.app"
