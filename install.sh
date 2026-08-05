#!/usr/bin/env bash
#
# Vineyard installer for macOS (Apple Silicon).
#
# Latest-version discovery, no version hardcoding:
#   1. GitHub API  -> exact release tag (rate limit: 60/h per IP, plenty)
#   2. Fallback    -> version-agnostic `releases/latest/download/…` URL,
#                     which always serves the newest build (works even when
#                     the API is rate-limited).
#
# curl downloads carry no quarantine attribute (that is a browser thing), so
# the installed app launches without Gatekeeper's "cannot verify" dialog.
# The xattr strip below is a belt-and-suspenders step, not the mechanism.
#
# Usage:
#   curl -fsSL https://whatabeautifulmemory.github.io/vineyard-website/install.sh | bash
#

set -euo pipefail

REPO="whatabeautifulmemory/vineyard-website"
ZIP="Vineyard-mac-arm64.zip"

# 1) Exact release via the GitHub API (tag name only, no jq needed).
URL=""
if LATEST="$(curl -fsSL --max-time 15 "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 2>/dev/null)" && [ -n "$LATEST" ]; then
    CANDIDATE="https://github.com/${REPO}/releases/download/${LATEST}/${ZIP}"
    if curl -fsIL --max-time 15 "$CANDIDATE" >/dev/null 2>&1; then
        URL="$CANDIDATE"
    fi
fi

# 2) Fallback: version-agnostic latest download.
if [ -z "$URL" ]; then
    URL="https://github.com/${REPO}/releases/latest/download/${ZIP}"
fi

echo "Vineyard: downloading ${URL}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fL --max-time 600 "$URL" -o "$TMP/vineyard.zip"
unzip -q "$TMP/vineyard.zip" -d "$TMP"
xattr -dr com.apple.quarantine "$TMP/Vineyard.app" 2>/dev/null || true

# Replace an existing install; quit a running instance first.
if [ -d /Applications/Vineyard.app ]; then
    osascript -e 'quit app "Vineyard"' >/dev/null 2>&1 || true
    sleep 1
    rm -rf /Applications/Vineyard.app
fi
mv "$TMP/Vineyard.app" /Applications/

echo "Vineyard installed."
echo "Open it with: open /Applications/Vineyard.app"
