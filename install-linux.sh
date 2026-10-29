#!/usr/bin/env bash
#
# Vineyard for Linux — one command, the right package for this machine.
#
#   curl -fsSL https://vineyard.run/install.sh | bash                   # the public command
#   curl -fsSL https://vineyard.run/install.sh | bash -s -- --dry-run   # say what it would install
#   bash install-linux.sh --dry-run                                    # this file, run directly
#
# The public command is install.sh, which is the same one line on macOS: it looks at `uname -s` and
# streams this file (served as https://vineyard.run/install-linux.sh, for anyone who wants to read
# what runs before running it) with the arguments passed through. Nothing here may assume it was
# run from a file — under `curl | bash` there is none, and $0 is just "bash".
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

# The help is a heredoc, not this file's header comment read back with `sed … "$0"`, which is what
# it used to be: under `curl | bash` $0 is "bash", so --help printed nothing — or, from a directory
# that happened to hold a file called bash, that file. Text kept here is the same however the
# script arrived, at the price of keeping it true by hand when the behaviour below changes.
usage() {
    cat <<EOF
Vineyard for Linux: downloads and installs the right package for this machine.

Usage:
  curl -fsSL https://vineyard.run/install.sh | bash
  curl -fsSL https://vineyard.run/install.sh | bash -s -- [option]

Options:
  --dry-run   say which file would be installed, and how, then stop
  -h, --help  show this help

What it installs, for x86_64 or ARM64 (aarch64):
  Debian, Ubuntu and their derivatives   the .deb, with apt (needs sudo)
  Arch, Omarchy and other Arch-based     the .pkg.tar.zst, with pacman (needs sudo)
  any other distribution                 the AppImage, as ~/.local/bin/vineyard (no sudo)

Every download is checked against the release's SHA256SUMS before it is installed.
All files: https://github.com/${REPO}/releases/latest
EOF
}

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h | --help) usage; exit 0 ;;
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
# ID_LIKE are read in a subshell so sourcing it cannot leak variables into this script. Its absence
# has to be survivable, and was not: a failed `.` made the substitution fail, `set -e` ended the
# script on the assignment, and a machine without the file got no install and no message at all —
# when "unknown distribution" is exactly the case the AppImage fallback below is for.
OS_ID="$( (. /etc/os-release && printf '%s' "${ID:-}") 2>/dev/null || true)"
OS_LIKE="$( (. /etc/os-release && printf '%s' "${ID_LIKE:-}") 2>/dev/null || true)"
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

# Root is needed for one thing: handing a package to apt or pacman. The AppImage is copied into the
# user's own ~/.local/bin and nothing else is touched, so it asks for no privilege — this used to
# die with "not root and no sudo" on that path too, refusing exactly the user (no sudo, a distro
# with no package for them) the AppImage fallback exists for.
SUDO=""
NO_SUDO=0
if [[ ${METHOD} != appimage && ${EUID} -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else NO_SUDO=1; fi
fi

# The choice is reported before a missing sudo is fatal, so --dry-run answers "what would it
# install" on a machine without sudo too, instead of stopping at the sudo error and never saying
# which file it had picked.
say "${OS_ID:-unknown distribution} / ${ARCH} → ${ASSET} (${METHOD}${SUDO:+, with sudo})"
NO_SUDO_MSG="installing the ${METHOD} package needs root, and sudo is not available — run this as root"
if [[ ${DRY_RUN} -eq 1 ]]; then
    [[ ${NO_SUDO} -eq 0 ]] || say "${NO_SUDO_MSG}"
    say "dry run — nothing downloaded or installed"
    exit 0
fi
[[ ${NO_SUDO} -eq 0 ]] || die "${NO_SUDO_MSG}"

# --- download, and check it against the release's checksums -------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

say "downloading ${ASSET}"
curl -fL --proto '=https' --tlsv1.2 --retry 2 -o "${TMP}/${ASSET}" "${BASE}/${ASSET}"
curl -fsSL --proto '=https' --tlsv1.2 -o "${TMP}/SHA256SUMS" "${BASE}/SHA256SUMS"

# The line is picked by the WHOLE file name: sha256sum writes "<hash>  <name>" ("<hash> *<name>" in
# binary mode), so the name is the second field and is compared for equality. This used to be a
# substring grep for "  <name>", which also took the line of any file whose name merely begins with
# this one (a "<name>.zsync", say); `sha256sum -c` then checked a file that was never downloaded
# and refused a good install. A missing line is a failure, not a skip: an asset that is not in
# SHA256SUMS is not one this release published.
SUM_LINE="$(awk -v f="${ASSET}" '$2 == f || $2 == "*" f' "${TMP}/SHA256SUMS")"
[[ -n ${SUM_LINE} ]] || die "${ASSET} is not listed in the release's SHA256SUMS — not installing it"
( cd "${TMP}" && printf '%s\n' "${SUM_LINE}" | sha256sum -c --status - ) \
    || die "checksum verification failed for ${ASSET} — not installing it"

# --- what the AppImage needs before it can start -------------------------------------------------
# Read off the shipped files (v0.4.70), not assumed. Both AppImages start with AppImageKit's type-2
# runtime, which dlopen()s libfuse.so.2 to mount itself — FUSE 2; a system with only fuse3 does not
# have it — and links zlib: libz.so.1 on x86_64, which every distribution has, but the bare
# development name libz.so on aarch64, which Debian and Ubuntu ship only in zlib1g-dev (Arch has it
# in zlib itself). An AppImage cannot declare a dependency, so this is the one place to say it.
#
# The question goes to the dynamic linker's cache, which is what the runtime will consult. Where
# ldconfig cannot be reached the library counts as missing and the note is printed anyway: a line
# of noise for someone who has it is cheaper than an app that will not start, with no hint why.
lib_cached() {
    local ldconfig cache
    ldconfig="$(command -v ldconfig 2>/dev/null || true)"
    [[ -n ${ldconfig} ]] || ldconfig=/sbin/ldconfig
    [[ -x ${ldconfig} ]] || return 1
    # Captured first, not piped into a reader that may stop early: under pipefail an ldconfig
    # killed by SIGPIPE would turn a found library into a missing one.
    cache="$("${ldconfig}" -p 2>/dev/null)" || return 1
    awk -v lib="$1" '$1 == lib { found = 1 } END { exit !found }' <<<"${cache}"
}

# The two are told apart because the way round one does not get round the other.
# --appimage-extract-and-run replaces the FUSE mount, so it is the answer to a missing libfuse.so.2
# only. libz.so is a NEEDED entry of the aarch64 runtime itself: without it the dynamic loader
# refuses the file before the runtime has read a single argument, so the same hint offered for a
# missing libz.so sent the user to a command that fails with the same error.
appimage_requirements() {
    local fuse=1 zlib=1
    lib_cached libfuse.so.2 || fuse=0
    if [[ ${ARCH} == aarch64 ]]; then
        lib_cached libz.so || zlib=0
    fi
    if [[ ${fuse} -eq 1 && ${zlib} -eq 1 ]]; then
        return 0
    fi
    say "the AppImage needs these libraries, which were not found on this system:"
    [[ ${fuse} -eq 1 ]] || printf '  %s\n' "libfuse.so.2 (FUSE 2)"
    [[ ${zlib} -eq 1 ]] || printf '  %s\n' "libz.so (zlib's development package)"
    say "install them with the distribution's package manager."
    if [[ ${zlib} -eq 0 ]]; then
        say "libz.so is needed however the AppImage is started: without it, it does not start at all."
    fi
    if [[ ${fuse} -eq 0 ]]; then
        if [[ ${zlib} -eq 1 ]]; then
            say "until FUSE 2 is installed it can still start, unpacked to a temporary folder each time:"
        else
            say "once libz.so is there, it can start without FUSE 2, unpacked to a temporary folder each time:"
        fi
        say "  ${START} --appimage-extract-and-run"
    fi
}

# --- install with the platform's own package manager --------------------------------------------
START="vineyard"
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
        say "installed to ${DEST}/vineyard"
        case ":${PATH}:" in
            *":${DEST}:"*) ;;
            *)
                START="${DEST}/vineyard"
                say "${DEST} is not on PATH — add it to PATH, or start Vineyard by its full path"
                ;;
        esac
        appimage_requirements
        ;;
esac

say "done — start it with: ${START}"
