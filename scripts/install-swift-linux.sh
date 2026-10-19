#!/usr/bin/env bash
# Installs the Swift toolchain pinned in .swift-version on Ubuntu 24.04 (x86_64 or aarch64).
#
# - Idempotent: exits 0 straight away when `swift --version` already reports the pinned version.
# - Installs the toolchain to /opt/swift/<version> and symlinks its binaries into /usr/local/bin.
# - Needs root, or passwordless sudo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/.swift-version")"
[[ -n "$VERSION" ]] || { echo "install-swift-linux: .swift-version is empty" >&2; exit 1; }

if swift --version 2>/dev/null | grep -q "Swift version $VERSION"; then
    echo "Swift $VERSION is already installed."
    exit 0
fi

case "$(uname -m)" in
    x86_64) PLATFORM="ubuntu2404"; SUFFIX="ubuntu24.04" ;;
    aarch64 | arm64) PLATFORM="ubuntu2404-aarch64"; SUFFIX="ubuntu24.04-aarch64" ;;
    *) echo "install-swift-linux: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then SUDO="sudo"; fi

# Dependencies documented by swift.org for Ubuntu 24.04, plus the SQLite headers ScratchCore links against.
echo "Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq --no-install-recommends \
    binutils ca-certificates curl git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
    libncurses-dev libpython3-dev libsqlite3-0 libsqlite3-dev libstdc++-13-dev libxml2-dev libz3-dev \
    pkg-config tzdata unzip zlib1g-dev

NAME="swift-$VERSION-RELEASE-$SUFFIX"
URL="https://download.swift.org/swift-$VERSION-release/$PLATFORM/swift-$VERSION-RELEASE/$NAME.tar.gz"
DEST="/opt/swift/$VERSION"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $URL"
curl --fail --location --silent --show-error --retry 5 --retry-delay 5 --retry-all-errors \
    --output "$WORK/$NAME.tar.gz" "$URL"

echo "Extracting to $DEST"
$SUDO rm -rf "$DEST" "$DEST.partial"
$SUDO mkdir -p "$DEST.partial"
$SUDO tar -xzf "$WORK/$NAME.tar.gz" -C "$DEST.partial" --strip-components=1
$SUDO mv "$DEST.partial" "$DEST"

for bin in "$DEST"/usr/bin/*; do
    $SUDO ln -sfn "$bin" "/usr/local/bin/$(basename "$bin")"
done

hash -r
swift --version
