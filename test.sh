#!/bin/zsh
# Checks the command builders against published HS60C packet captures.
set -e
cd "$(dirname "$0")"
CACHE="${TMPDIR:-/tmp}/neewerlight-modcache"
OUT="${TMPDIR:-/tmp}/neewerlight-verify"
mkdir -p "$CACHE"
swiftc -module-cache-path "$CACHE" -o "$OUT" \
  Sources/NeewerLight/Protocol.swift Sources/NeewerLight/Effects.swift Tests/main.swift
"$OUT"
