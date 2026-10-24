#!/usr/bin/env bash
#
# Vineyard for Linux — one command, the right package for this machine.
#
#   curl -fsSL https://vineyard.run/linux-install.sh | bash
#   ./linux-install.sh --dry-run     # say what it would install, and stop
#
# WHY THIS EXISTS. There are six artefacts: deb, pacman and AppImage, each for x86_64 and aarch64.
# Picking the wrong one does not fail gently — pacman calls a foreign architecture "invalid", and
# an AppImage of the wrong architecture is "Exec format error" — so the decision belongs in one
# place that knows how to make it, not in a download page that asks the reader to run `uname -m`
# and recognise their own distribution.
#
# Nothing is installed that the platform's own package manager cannot then see: a deb goes through
# apt, a pacman package through pacman. Only a distribution with neither (Fedora, openSUSE, …)
# falls back to an AppImage in ~/.local/bin.
set -euo pipefail

REPO="whatabeautifulmemory/vineyard-website"
BASE="https://github.com/${REPO}/releases/latest/download"

say() { printf 'vineyard: %s\n' "$*"; }
die() { printf 'vineyard: %s\n' "$*" >&2; exit 1; }

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $arg (try --help)" ;;
    esac
done

# --- what is this machine -----------------------------------------------------------------------
case "$(uname -m)" in
    x86_64 | amd64) ARCH=x86_64 ;;
    aarch64 | arm64) ARCH=aarch64 ;;
    *) die "unsupported architecture: $(uname -m) — Vineyard ships for x86_64 and aarch64" ;;
esac

# os-release is the only source that is present on every distribution worth supporting. ID and
# ID_LIKE are read in a subshell so sourcing it cannot leak variables into this script.
OS_ID="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}")"
OS_LIKE="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID_LIKE:-}")"
FAMILY=unknown
case " ${OS_ID} ${OS_LIKE} " in
    *" arch "*) FAMILY=arch ;;
    *" debian "* | *" ubuntu "*) FAMILY=deb ;;
esac

case "${FAMILY}:${ARCH}" in
    deb:x86_64) ASSET="Vineyard-linux-amd64.deb"; METHOD=deb ;;
    deb:aarch64) ASSET="Vineyard-linux-arm64.deb"; METHOD=deb ;;
    arch:x86_64) ASSET="Vineyard-linux-x86_64.pkg.tar.zst"; METHOD=pacman ;;
    arch:aarch64) ASSET="Vineyard-linux-aarch64.pkg.tar.zst"; METHOD=pacman ;;
    *:x86_64) ASSET="Vineyard-linux-x86_64.AppImage"; METHOD=appimage ;;
    *:aarch64) ASSET="Vineyard-linux-aarch64.AppImage"; METHOD=appimage ;;
esac

SUDO=""
if [[ ${EUID} -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die "not root and no sudo — run this as root"
    SUDO="sudo"
fi

say "${OS_ID:-unknown distribution} / ${ARCH} → ${ASSET} (${METHOD})"
if [[ ${DRY_RUN} -eq 1 ]]; then
    say "dry run — nothing downloaded or installed"
    exit 0
fi

# --- download, and check it against the release's checksums -------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

say "downloading ${ASSET}"
curl -fL --proto '=https' --tlsv1.2 --retry 2 -o "${TMP}/${ASSET}" "${BASE}/${ASSET}"
curl -fsSL --proto '=https' --tlsv1.2 -o "${TMP}/SHA256SUMS" "${BASE}/SHA256SUMS"

# The check is done on the exact line, and a missing line is a failure: an asset that is not in
# SHA256SUMS is not one this release published.
( cd "${TMP}" && grep -F "  ${ASSET}" SHA256SUMS | sha256sum -c --status - ) \
    || die "checksum verification failed for ${ASSET} — not installing it"

# --- install with the platform's own package manager --------------------------------------------
case "${METHOD}" in
    deb)
        say "installing with apt"
        ${SUDO} apt-get install -y "${TMP}/${ASSET}"
        ;;
    pacman)
        say "installing with pacman"
        ${SUDO} pacman -U --noconfirm "${TMP}/${ASSET}"
        ;;
    appimage)
        # No package manager for this family, so the AppImage is placed where a user-local binary
        # belongs and nothing else on the system is touched.
        DEST="${HOME}/.local/bin"
        mkdir -p "${DEST}"
        install -m 755 "${TMP}/${ASSET}" "${DEST}/vineyard"
        say "installed to ${DEST}/vineyard (add that directory to PATH if it is not there already)"
        ;;
esac

say "done — start it with: vineyard"
