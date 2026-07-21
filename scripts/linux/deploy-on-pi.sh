#!/usr/bin/env bash
#
# deploy-on-pi.sh — run on your PC from a Shipwright-CRT checkout.
#
# Syncs this tree to the Pi (no git clone on the Pi), mounts the Pi build
# image, builds the aarch64 release zip there, and copies it back to
# ./_packages/build-linux-arm64/.
#
# Usage:
#   ./scripts/linux/deploy-on-pi.sh IP=192.168.1.10 USER=pi PASS=secret
#
# Also accepts env vars: IP, USER / PI_USER, PASS / PI_PASS.
# Optional: --no-build (sync only), SUDO_PWD=... (defaults to PASS for loop mount).
#
# Requires on the PC: sshpass, and either rsync or tar.
# Pi build image: /media/sd/soh-build.img (created automatically if missing).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

PI_IP="${IP:-}"
PI_USER="${PI_USER:-}"
PI_PASS="${PI_PASS:-}"
DO_BUILD=1

for arg in "$@"; do
    case "$arg" in
        --no-build) DO_BUILD=0 ;;
        IP=*) PI_IP="${arg#*=}" ;;
        USER=*|PI_USER=*) PI_USER="${arg#*=}" ;;
        PASS=*|PI_PASS=*|PWD=*) PI_PASS="${arg#*=}" ;;
        SUDO_PWD=*) SUDO_PWD="${arg#*=}" ;;
        -h|--help)
            sed -n '2,18p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 IP=192.168.1.10 USER=pi PASS=secret [--no-build]" >&2
            exit 2
            ;;
    esac
done

if [ -z "$PI_IP" ] || [ -z "$PI_USER" ] || [ -z "$PI_PASS" ]; then
    echo "ERROR: need IP, USER, and PASS." >&2
    echo "  Example: $0 IP=192.168.1.10 USER=pi PASS=secret" >&2
    exit 2
fi

SUDO_PWD="${SUDO_PWD:-$PI_PASS}"

if [ ! -f "$ROOT/libultraship/CMakeLists.txt" ]; then
    echo "ERROR: submodules missing. From $ROOT run:" >&2
    echo "  git submodule update --init --recursive" >&2
    exit 1
fi

command -v sshpass >/dev/null 2>&1 || {
    echo "ERROR: sshpass not found (e.g. sudo pacman -S sshpass / sudo apt install sshpass)" >&2
    exit 1
}

export SSHPASS="$PI_PASS"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
sshpi() { sshpass -e ssh "${SSH_OPTS[@]}" "${PI_USER}@${PI_IP}" "$@"; }
scppi() { sshpass -e scp "${SSH_OPTS[@]}" "$@"; }

REMOTE="${PI_USER}@${PI_IP}"
IMG="${SOH_BUILD_IMG:-/media/sd/soh-build.img}"
MOUNT="${SOH_BUILD_MOUNT:-/home/${PI_USER}/soh-build}"
TREE="${SOH_BUILD_TREE:-${MOUNT}/Shipwright-CRT}"
REMOTE_OUT="${TREE}/_packages/build-linux-arm64"
LOCAL_OUT="$ROOT/_packages/build-linux-arm64"

echo ">> Target: $REMOTE"
echo ">> Remote tree: $TREE"

echo ">> Ensuring build image exists and is mounted on the Pi..."
# Copy helper first so we can create the image before the tree sync.
scppi "$ROOT/scripts/linux/ensure-pi-build-img.sh" "${REMOTE}:/tmp/ensure-pi-build-img.sh"
sshpi "export SOH_BUILD_IMG=$(printf '%q' "$IMG")
export SOH_BUILD_MOUNT=$(printf '%q' "$MOUNT")
export SOH_BUILD_IMG_SIZE=$(printf '%q' "${SOH_BUILD_IMG_SIZE:-8G}")
export SUDO_PWD=$(printf '%q' "$SUDO_PWD")
bash /tmp/ensure-pi-build-img.sh
mkdir -p $(printf '%q' "$TREE")
"

echo ">> Syncing sources to the Pi (excludes .git / build-cmake / _packages)..."
# rsync keeps the Pi's build-cmake (excluded) so rebuilds stay incremental.
RSYNC_EXCLUDES=(
    --exclude '.git/'
    --exclude 'build-cmake/'
    --exclude '_packages/'
    --exclude '.portable-tools/'
    --exclude 'dist/'
    --exclude '.cache/'
    --exclude 'imgui.ini'
    --exclude 'logs/'
    --exclude '*.o2r'
    --exclude 'base_rom.z64'
)

if command -v rsync >/dev/null 2>&1; then
    rsync -az --delete \
        -e "sshpass -e ssh ${SSH_OPTS[*]}" \
        "${RSYNC_EXCLUDES[@]}" \
        "$ROOT/" "${REMOTE}:${TREE}/"
else
    echo ">> rsync not found; using tar stream..."
    TMP_TAR="$(mktemp -t soh-crt-XXXXXX.tar.gz)"
    cleanup() { rm -f "$TMP_TAR"; }
    trap cleanup EXIT
    tar -C "$ROOT" -czf "$TMP_TAR" \
        --exclude='.git' \
        --exclude='build-cmake' \
        --exclude='_packages' \
        --exclude='.portable-tools' \
        --exclude='dist' \
        --exclude='.cache' \
        --exclude='imgui.ini' \
        --exclude='logs' \
        --exclude='*.o2r' \
        --exclude='base_rom.z64' \
        .
    scppi "$TMP_TAR" "${REMOTE}:/tmp/soh-crt-src.tar.gz"
    sshpi "mkdir -p '$TREE' && tar -xzf /tmp/soh-crt-src.tar.gz -C '$TREE' && rm -f /tmp/soh-crt-src.tar.gz"
fi

if [ "$DO_BUILD" -eq 0 ]; then
    echo ">> Sync done (--no-build). On the Pi run:"
    echo "   HOST_TARGET=pi $TREE/scripts/linux/appimage/build.sh"
    exit 0
fi

echo ">> Building AppImage on the Pi (this can take a while)..."
# Quote carefully: password may contain special characters.
sshpi "export HOST_TARGET=pi
export SUDO_PWD=$(printf '%q' "$SUDO_PWD")
export SOH_BUILD_IMG=$(printf '%q' "$IMG")
export SOH_BUILD_MOUNT=$(printf '%q' "$MOUNT")
export SOH_BUILD_TREE=$(printf '%q' "$TREE")
cd $(printf '%q' "$TREE")
bash ./scripts/linux/appimage/build.sh
"

if [ ! -f "$ROOT/CRT_VERSION" ]; then
    echo "ERROR: missing $ROOT/CRT_VERSION" >&2
    exit 1
fi
CRT_VERSION="$(tr -d '[:space:]' < "$ROOT/CRT_VERSION")"
RELEASE_ZIP="soh-raspberry-pi-${CRT_VERSION}.zip"

echo ">> Copying Pi release zip back to $LOCAL_OUT ..."
mkdir -p "$LOCAL_OUT"
# Keep only the current release zip locally.
find "$LOCAL_OUT" -maxdepth 1 -type f -name 'soh-raspberry-pi-*.zip' ! -name "$RELEASE_ZIP" -delete 2>/dev/null || true
scppi "${REMOTE}:${REMOTE_OUT}/${RELEASE_ZIP}" "$LOCAL_OUT/"

echo
echo ">> Done."
ls -lah "$LOCAL_OUT"
echo "   Release zip: $LOCAL_OUT/$RELEASE_ZIP"
echo "   PC builds land in _packages/build-linux-x86_64/."
