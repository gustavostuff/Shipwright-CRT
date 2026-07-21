#!/usr/bin/env bash
#
# Mount the Pi build image and git-clone Shipwright-CRT onto it.
# Run this ON the Raspberry Pi (not on your PC).
#
#   curl -fsSL https://raw.githubusercontent.com/gustavostuff/Shipwright-CRT/develop/scripts/linux/pi-clone.sh \
#     -o /tmp/pi-clone.sh && chmod +x /tmp/pi-clone.sh && /tmp/pi-clone.sh
#
# Or copy this file over with scp and run it.
#
# Env overrides: SOH_BUILD_IMG, SOH_BUILD_MOUNT, SOH_BUILD_TREE, SOH_GIT_URL, SUDO_PWD
#

set -euo pipefail

IMG="${SOH_BUILD_IMG:-/media/sd/soh-build.img}"
MOUNT="${SOH_BUILD_MOUNT:-$HOME/soh-build}"
TREE="${SOH_BUILD_TREE:-$MOUNT/Shipwright-CRT}"
GIT_URL="${SOH_GIT_URL:-https://github.com/gustavostuff/Shipwright-CRT.git}"
BRANCH="${SOH_GIT_BRANCH:-develop}"

if [ ! -f "$IMG" ]; then
    echo "ERROR: build image not found: $IMG" >&2
    exit 1
fi

if ! mountpoint -q "$MOUNT"; then
    echo ">> Mounting $IMG -> $MOUNT ..."
    mkdir -p "$MOUNT"
    if [ -n "${SUDO_PWD:-}" ]; then
        echo "$SUDO_PWD" | sudo -S mount -o loop "$IMG" "$MOUNT"
    else
        sudo mount -o loop "$IMG" "$MOUNT"
    fi
else
    echo ">> Already mounted: $MOUNT"
fi

echo ">> Mount info:"
findmnt "$MOUNT" || true
df -h "$MOUNT"

if [ -e "$TREE" ]; then
    echo ">> Removing existing $TREE ..."
    rm -rf "$TREE"
fi

echo ">> Cloning $GIT_URL (branch $BRANCH) into $TREE ..."
# --jobs parallelizes submodule fetches; helps when the link is fine but serial clone feels stuck.
git clone --recursive --jobs="$(nproc)" --branch "$BRANCH" "$GIT_URL" "$TREE"

echo
echo ">> Done. Tree: $TREE"
echo "   Build with:"
echo "   HOST_TARGET=pi \"$TREE/scripts/linux/appimage/build.sh\""
