#!/usr/bin/env bash
#
# Ensure the Pi build loop image exists and is mounted.
# Creates + formats it if missing (can take a while on SD media).
#
# Env:
#   SOH_BUILD_IMG       default /media/sd/soh-build.img
#   SOH_BUILD_MOUNT     default $HOME/soh-build
#   SOH_BUILD_IMG_SIZE  default 8G (truncate/fallocate size, or dd count via 8G)
#   SUDO_PWD            optional; piped to sudo -S when set
#
# Safe to run multiple times. Intended for the Pi (or over ssh).
#

set -euo pipefail

IMG="${SOH_BUILD_IMG:-/media/sd/soh-build.img}"
MOUNT="${SOH_BUILD_MOUNT:-$HOME/soh-build}"
SIZE="${SOH_BUILD_IMG_SIZE:-8G}"

sudo_run() {
    if [ -n "${SUDO_PWD:-}" ]; then
        echo "$SUDO_PWD" | sudo -S "$@"
    else
        sudo "$@"
    fi
}

if [ ! -f "$IMG" ]; then
    echo ">> Build image not found: $IMG"
    echo ">> Creating a new ${SIZE} ext4 image (this may take a while on SD/USB)..."
    IMG_DIR="$(dirname "$IMG")"
    sudo_run mkdir -p "$IMG_DIR"

    # Prefer fast allocate; fall back to full dd write (slower, works on more filesystems).
    if command -v fallocate >/dev/null 2>&1 && sudo_run fallocate -l "$SIZE" "$IMG" 2>/dev/null; then
        echo ">> Allocated $IMG with fallocate"
    elif sudo_run truncate -s "$SIZE" "$IMG" 2>/dev/null; then
        echo ">> Allocated $IMG with truncate"
    else
        echo ">> fallocate/truncate failed; writing zeros with dd (slow)..."
        # SIZE like 8G -> 8192 MiB
        local_mib="$(echo "$SIZE" | awk '
            /^[0-9]+[Gg]$/ { printf "%d", $0 * 1024; next }
            /^[0-9]+[Mm]$/ { printf "%d", $0 + 0; next }
            /^[0-9]+$/ { print; next }
            { print 8192 }
        ')"
        sudo_run dd if=/dev/zero of="$IMG" bs=1M count="$local_mib" status=progress
    fi

    echo ">> Formatting $IMG as ext4..."
    sudo_run mkfs.ext4 -F "$IMG"
    echo ">> Build image ready: $IMG"
else
    echo ">> Build image present: $IMG"
fi

mkdir -p "$MOUNT"
if ! mountpoint -q "$MOUNT"; then
    echo ">> Mounting $IMG -> $MOUNT ..."
    sudo_run mount -o loop "$IMG" "$MOUNT"
else
    echo ">> Already mounted: $MOUNT"
fi
