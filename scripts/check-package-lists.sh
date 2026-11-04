#!/bin/bash
# scripts/check-package-lists.sh
# Validates every package name used by the image against the real Debian
# archive, so a typo fails in seconds instead of aborting live-build after a
# full debootstrap (e.g. "xrandr" instead of "x11-xserver-utils").
#
# SUITE, ARCH, MIRROR and AREAS can be overridden from the environment.

set -euo pipefail

SUITE="${SUITE:-trixie}"
ARCH="${ARCH:-amd64}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
AREAS="${AREAS:-main contrib non-free non-free-firmware}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TMP_DIR="$(mktemp -d /tmp/pkgcheck-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== Checking package names against ${SUITE} (${ARCH}) ==="

: > "$TMP_DIR/packages.txt"
for AREA in $AREAS; do
    for BINARCH in "$ARCH" all; do
        URL="${MIRROR}/dists/${SUITE}/${AREA}/binary-${BINARCH}/Packages.xz"
        if curl -fsSL -o "$TMP_DIR/packages.xz" "$URL"; then
            xz -dc "$TMP_DIR/packages.xz" \
                | awk '/^Package: /{print $2}' >> "$TMP_DIR/packages.txt"
        else
            echo "WARNING: cannot download ${URL}" >&2
        fi
    done
done

sort -u -o "$TMP_DIR/packages.txt" "$TMP_DIR/packages.txt"
if [ ! -s "$TMP_DIR/packages.txt" ]; then
    echo "ERROR: no package index could be downloaded from ${MIRROR}" >&2
    exit 1
fi
echo "archive packages: $(wc -l < "$TMP_DIR/packages.txt")"

MISSING=0

check_name() {
    local NAME="$1"
    local SOURCE="$2"

    case "$NAME" in
        ''|'#'*) return 0 ;;
    esac

    if ! grep -qxF "$NAME" "$TMP_DIR/packages.txt"; then
        echo "ERROR: ${SOURCE}: package '${NAME}' does not exist in ${SUITE}" >&2
        MISSING=1
    fi
}

for LIST in "$REPO_ROOT"/config/package-lists/*.list.*; do
    [ -f "$LIST" ] || continue
    while IFS= read -r LINE; do
        LINE="${LINE%%#*}"
        LINE="$(printf '%s' "$LINE" | tr -d '\r' | xargs)"
        check_name "$LINE" "${LIST#"$REPO_ROOT"/}"
    done < "$LIST"
done

# The Calamares packages module installs into the target system, so it has to
# stay valid for the same suite the live image is built from.
CALAMARES_PACKAGES="$REPO_ROOT/config/includes.chroot/etc/calamares/modules/packages.conf"
if [ -f "$CALAMARES_PACKAGES" ]; then
    while IFS= read -r LINE; do
        case "$LINE" in
            '  - '*)
                NAME="$(printf '%s' "$LINE" | sed 's/^  - //' | tr -d '\r' | xargs)"
                check_name "$NAME" "${CALAMARES_PACKAGES#"$REPO_ROOT"/}"
                ;;
        esac
    done < "$CALAMARES_PACKAGES"
fi

if [ "$MISSING" -ne 0 ]; then
    echo "=== FAILED: fix the package names above ===" >&2
    exit 1
fi

echo "=== OK: every package name exists in ${SUITE} ==="
