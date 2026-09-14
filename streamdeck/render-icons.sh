#!/bin/zsh
# Regenerate the plugin's PNG icons from the SVG sources.
# Stream Deck manifests want PNG + @2x, so the SVGs are the source and these are built.
set -e
cd "$(dirname "$0")"
CACHE="${TMPDIR:-/tmp}/neewerlight-modcache"
BIN="${TMPDIR:-/tmp}/neewer-rasterize"
mkdir -p "$CACHE"
swiftc -module-cache-path "$CACHE" -o "$BIN" tools/rasterize.swift
for f in com.jonpike.neewerdeck.sdPlugin/imgs/*.svg; do
  "$BIN" "$f" "${f%.svg}"
done
echo "Rendered $(ls com.jonpike.neewerdeck.sdPlugin/imgs/*.png | wc -l | tr -d ' ') PNGs"
