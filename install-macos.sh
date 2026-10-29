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
# Usage (install.sh dispatches here on macOS, with the arguments passed through):
#   curl -fsSL https://vineyard.run/install.sh | bash
#   curl -fsSL https://vineyard.run/install.sh | bash -s -- --dry-run
#

set -euo pipefail

# The wrong installer for the platform fails in a way that reads as a broken release. One line here
# is cheaper than letting a Linux user work out why a .app does not appear. The pointer is to
# install.sh, the one public command, which picks install-linux.sh there — it used to name a
# linux-install.sh that was never published, and vineyard.run answers an unknown path with the
# landing page, so following the advice piped HTML into bash.
if [ "$(uname -s)" = "Linux" ]; then
    echo "vineyard: this installer is for macOS. On Linux run:" >&2
    echo "  curl -fsSL https://vineyard.run/install.sh | bash" >&2
    exit 1
fi

# install.sh hands every argument through, and the Linux side honours --dry-run and --help. This
# side used to ignore its arguments altogether, so the same `--dry-run` that only looks on Linux
# went ahead and replaced /Applications/Vineyard.app on a Mac.
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h | --help)
            cat <<'EOF'
Vineyard for macOS (Apple Silicon): installs the latest build into /Applications.

Usage:
  curl -fsSL https://vineyard.run/install.sh | bash
  curl -fsSL https://vineyard.run/install.sh | bash -s -- [option]

Options:
  --dry-run   say what would be downloaded, then stop
  -h, --help  show this help
EOF
            exit 0
            ;;
        *)
            echo "vineyard: unknown option: $arg (try --help)" >&2
            exit 1
            ;;
    esac
done

# The only macOS build is arm64. On an Intel Mac it would download, unpack and land in
# /Applications as an app that cannot start, which reads as a broken release rather than an
# unsupported machine. `uname -m` alone cannot say so: a shell running under Rosetta reports x86_64
# on Apple Silicon too. So x86_64 is only the cue to ask hw.optional.arm64, which is 1 on Apple
# Silicon under Rosetta and absent on Intel — and a native arm64 shell is never asked at all, so
# nothing about this check can refuse the machine the build is for.
if [ "$(uname -m)" = "x86_64" ] && [ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" ]; then
    echo "vineyard: the macOS build is for Apple Silicon (M1 and later) only." >&2
    echo "  On an Intel Mac, use the web app: https://app.vineyard.run" >&2
    exit 1
fi

REPO="whatabeautifulmemory/vineyard-website"
ZIP="Vineyard-mac-arm64.zip"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Vineyard: would download the latest ${ZIP} from github.com/${REPO}"
    echo "Vineyard: and install it as /Applications/Vineyard.app — dry run, nothing downloaded or installed"
    exit 0
fi

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
