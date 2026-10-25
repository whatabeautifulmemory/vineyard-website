#!/usr/bin/env bash
#
# Vineyard installer — the one URL, dispatched by platform.
#
#   curl -fsSL https://vineyard.run/install.sh | bash
#
# This used to BE the macOS installer, and the name was a lie the moment Linux shipped: a Linux
# visitor who copied it got an error about a .app that would never appear. The platform-specific
# scripts still exist (install-macos.sh, install-linux.sh) for anyone who wants to read what runs,
# but the public command is one line on every platform and the choice is made here.
set -euo pipefail

case "$(uname -s)" in
    Darwin) SCRIPT="install-macos.sh" ;;
    Linux) SCRIPT="install-linux.sh" ;;
    *)
        echo "vineyard: unsupported operating system: $(uname -s)" >&2
        echo "  macOS and Linux have installers; Windows has an .exe on the releases page." >&2
        exit 1
        ;;
esac

# Streamed, not parsed: both scripts are self-contained, and passing "$@" through keeps
# `--dry-run` working on the Linux side.
curl -fsSL "https://vineyard.run/${SCRIPT}" | bash -s -- "$@"
