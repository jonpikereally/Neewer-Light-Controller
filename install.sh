#!/bin/zsh
# Install (or update) the app in ~/Applications, and the Stream Deck plugin.
# The app can't run from Dropbox/CloudStorage — macOS kills it with
# "the application is not open anymore" — so it has to be copied out.
set -e
cd "$(dirname "$0")"

# The in-app updater has already built the app, so it sets SKIP_BUILD, and passes DEST
# so the update lands wherever the running copy lives.
[[ -n "$SKIP_BUILD" ]] || ./build.sh
DEST="${DEST:-$HOME/Applications/Neewer Light.app}"
rm -rf "$DEST"
ditto NeewerLight.app "$DEST"
codesign --force --sign - "$DEST"
echo "Installed $DEST"

# --- Stream Deck plugin ------------------------------------------------------
PLUGINS="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins"
PLUGIN="com.jonpike.neewerdeck.sdPlugin"
if [[ -d "$PLUGINS" ]]; then
  if pgrep -xq "Stream Deck"; then
    echo "Quitting Stream Deck to swap the plugin…"
    osascript -e 'quit app "Stream Deck"' || true
    for i in {1..20}; do pgrep -xq "Stream Deck" || break; sleep 0.5; done
  fi
  rm -rf "$PLUGINS/$PLUGIN"
  ditto "streamdeck/$PLUGIN" "$PLUGINS/$PLUGIN"
  echo "Installed $PLUGINS/$PLUGIN"
  open -a "Stream Deck" || echo "Start Stream Deck manually to load the plugin."
else
  echo "Stream Deck not found — skipped the plugin."
fi

echo
echo "Launch 'Neewer Light' from Spotlight, then add the Neewer Deck actions in Stream Deck."
