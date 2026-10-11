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

# Build stamp, shown in the popover and used by the updater to tell whether a newer
# commit exists. The in-app updater builds from a GitHub tarball (no .git), so it
# passes these in; otherwise they come from git.
COMMIT="${NEEWER_COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
BUILD="${NEEWER_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
mkdir -p NeewerLight.app/Contents/Resources
cat > NeewerLight.app/Contents/Resources/BuildInfo.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Commit</key>  <string>$COMMIT</string>
    <key>Build</key>   <string>$BUILD</string>
    <key>BuiltAt</key> <string>$(date -u +%Y-%m-%dT%H:%M:%SZ)</string>
</dict>
</plist>
PLIST

codesign --force --sign - NeewerLight.app
echo "Built NeewerLight.app (build $BUILD, ${COMMIT:0:7})"
