#!/usr/bin/env bash
#
# Build Ship of Harkinian CRT as a Linux AppImage (PC or Pi).
#
# Usage:
#   # PC (from a normal checkout):
#   ./scripts/linux/appimage/build.sh
#   HOST_TARGET=pc ./scripts/linux/appimage/build.sh
#
#   # Pi (run ON the Pi). Do NOT git-clone onto the tiny rootfs.
#   # Mounts /media/sd/soh-build.img -> ~/soh-build, clones into that image,
#   # then builds there. Bootstrap from /tmp if you have no checkout yet:
#   curl -fsSL https://raw.githubusercontent.com/gustavostuff/Shipwright-CRT/main/scripts/linux/appimage/build.sh \
#     -o /tmp/soh-crt-build.sh && chmod +x /tmp/soh-crt-build.sh
#   HOST_TARGET=pi /tmp/soh-crt-build.sh
#   # or, if already on the image checkout:
#   HOST_TARGET=pi ./scripts/linux/appimage/build.sh
#
# Native build only: no PC -> Pi cross-compile. If HOST_TARGET is unset,
# aarch64/arm64 => pi, otherwise => pc.
#
# Pi env overrides:
#   SOH_BUILD_IMG    loop image (default /media/sd/soh-build.img)
#   SOH_BUILD_MOUNT  mount point (default ~/soh-build)
#   SOH_BUILD_TREE   clone/build dir (default $SOH_BUILD_MOUNT/Shipwright-CRT)
#   SOH_GIT_URL      clone URL (default github.com/gustavostuff/Shipwright-CRT.git)
#   SUDO_PWD         piped to sudo -S for the loop mount (no prompt)
#
# Output: _packages/soh-pc.AppImage or soh-raspberry-pi.AppImage
#         plus shipofharkinian.json and proggy-tiny.ttf beside it.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If this file lives in a real checkout, remember that path (may be on a full rootfs).
INVOKED_ROOT=""
if [ -f "$SCRIPT_DIR/../../../CMakeLists.txt" ] && [ -d "$SCRIPT_DIR/../../../soh" ]; then
    INVOKED_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

HOST_ARCH="$(uname -m)"
if [ -z "${HOST_TARGET:-}" ]; then
    case "$HOST_ARCH" in
        aarch64|arm64) HOST_TARGET=pi ;;
        *) HOST_TARGET=pc ;;
    esac
fi

case "$HOST_TARGET" in
    pc)
        FULLSCREEN=false
        WIN_W=320
        WIN_H=240
        APPIMAGE_NAME="soh-pc.AppImage"
        if [ -z "$INVOKED_ROOT" ]; then
            echo "ERROR: on PC, run this script from a Shipwright-CRT checkout." >&2
            exit 2
        fi
        ROOT="$INVOKED_ROOT"
        ;;
    pi)
        case "$HOST_ARCH" in
            aarch64|arm64) ;;
            *)
                echo "ERROR: HOST_TARGET=pi must be run on the Pi (aarch64), not cross-built from $HOST_ARCH." >&2
                echo "       SSH into the Pi and run: HOST_TARGET=pi ./scripts/linux/appimage/build.sh" >&2
                exit 2
                ;;
        esac
        FULLSCREEN=true
        WIN_W=
        WIN_H=
        APPIMAGE_NAME="soh-raspberry-pi.AppImage"

        # Rootfs is too small for clone+build. Use a loop-mounted ext4 image.
        IMG="${SOH_BUILD_IMG:-/media/sd/soh-build.img}"
        MOUNT="${SOH_BUILD_MOUNT:-$HOME/soh-build}"
        TREE="${SOH_BUILD_TREE:-$MOUNT/Shipwright-CRT}"
        GIT_URL="${SOH_GIT_URL:-https://github.com/gustavostuff/Shipwright-CRT.git}"

        if [ ! -f "$IMG" ]; then
            echo "ERROR: Pi build image not found: $IMG" >&2
            echo "       Place an ext4 image there, or set SOH_BUILD_IMG / SOH_BUILD_MOUNT." >&2
            exit 1
        fi
        if ! mountpoint -q "$MOUNT"; then
            echo ">> Mounting build image $IMG -> $MOUNT ..."
            mkdir -p "$MOUNT"
            if [ -n "${SUDO_PWD:-}" ]; then
                echo "$SUDO_PWD" | sudo -S mount -o loop "$IMG" "$MOUNT"
            else
                sudo mount -o loop "$IMG" "$MOUNT"
            fi
        else
            echo ">> Build image already mounted at $MOUNT"
        fi

        # Prefer an already-complete tree on the image; otherwise clone there.
        if [ -n "$INVOKED_ROOT" ] && [[ "$INVOKED_ROOT" == "$MOUNT"/* ]] &&
            [ -f "$INVOKED_ROOT/libultraship/CMakeLists.txt" ]; then
            TREE="$INVOKED_ROOT"
            echo ">> Using checkout on build image: $TREE"
        elif [ -f "$TREE/libultraship/CMakeLists.txt" ]; then
            echo ">> Using existing tree on build image: $TREE"
        else
            if [ -n "$INVOKED_ROOT" ] && [ -d "$INVOKED_ROOT/.git" ]; then
                GIT_URL="$(git -C "$INVOKED_ROOT" remote get-url origin 2>/dev/null || echo "$GIT_URL")"
            fi
            if [ -d "$TREE/.git" ]; then
                echo ">> Completing incomplete checkout at $TREE ..."
                git -C "$TREE" submodule update --init --recursive
            else
                echo ">> Cloning into $TREE (on build image; avoids filling the rootfs) ..."
                rm -rf "$TREE"
                git clone --recursive "$GIT_URL" "$TREE"
            fi
        fi

        if [ ! -f "$TREE/libultraship/CMakeLists.txt" ]; then
            echo "ERROR: tree at $TREE is still missing libultraship after clone/update." >&2
            exit 1
        fi

        if [ -n "$INVOKED_ROOT" ] && [[ "$INVOKED_ROOT" != "$MOUNT"/* ]]; then
            echo "WARNING: you also have a checkout outside the build image: $INVOKED_ROOT" >&2
            echo "         That is what usually fills the Pi rootfs. After this build succeeds," >&2
            echo "         free space with:  rm -rf '$INVOKED_ROOT'" >&2
        fi

        ROOT="$TREE"
        ;;
    *)
        echo "ERROR: HOST_TARGET must be pc or pi (got: $HOST_TARGET)" >&2
        exit 2
        ;;
esac

cd "$ROOT"
CONFIG_DIR="$ROOT/config"
PACKAGES="$ROOT/_packages"

echo ">> Shipwright-CRT AppImage build (HOST_TARGET=$HOST_TARGET, arch=$HOST_ARCH)"
echo ">> Tree: $ROOT"

if [ ! -f "$ROOT/libultraship/CMakeLists.txt" ]; then
    echo ">> Initializing submodules..."
    git submodule update --init --recursive
fi

for t in cmake ninja git python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "ERROR: missing tool: $t" >&2; exit 1; }
done

echo ">> Configuring..."
cmake --no-warn-unused-cli -S "$ROOT" -B "$ROOT/build-cmake" -G Ninja -DCMAKE_BUILD_TYPE:STRING=Release

echo ">> Building..."
cmake --build "$ROOT/build-cmake" --config Release --

# soh.o2r is required by install/cpack (embedded in the AppImage). Default `soh`
# build does not produce it — same as upstream docs/BUILDING.md.
echo ">> Generating soh.o2r (GenerateSohOtr)..."
cmake --build "$ROOT/build-cmake" --config Release --target GenerateSohOtr

echo ">> Packaging AppImage (cpack External / linuxdeploy)..."
mkdir -p "$PACKAGES"
(cd "$ROOT/build-cmake" && cpack -G External)

# CPack also writes a Ship-*-*.json metadata stub; not part of the CRT runtime.
rm -f "$PACKAGES"/Ship-*.json

# Prefer _packages/. Fall back to build-cmake if linuxdeploy used a relative OUTPUT
# (legacy Packaging.cmake behavior: Ship-*.appimage next to the build tree).
pick_appimage() {
    local dir="$1"
    find "$dir" -maxdepth 1 -type f \( -iname '*.AppImage' \) ! -iname 'linuxdeploy*' \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-
}

FOUND="$(pick_appimage "$PACKAGES" || true)"
if [ -z "$FOUND" ] || [ ! -f "$FOUND" ]; then
    FALLBACK="$(pick_appimage "$ROOT/build-cmake" || true)"
    if [ -n "$FALLBACK" ] && [ -f "$FALLBACK" ]; then
        echo ">> Moving $(basename "$FALLBACK") into $PACKAGES"
        mv -f "$FALLBACK" "$PACKAGES/"
        FOUND="$PACKAGES/$(basename "$FALLBACK")"
    fi
fi
if [ -z "$FOUND" ] || [ ! -f "$FOUND" ]; then
    echo "ERROR: no AppImage found under $PACKAGES (or build-cmake/)" >&2
    ls -la "$PACKAGES" "$ROOT/build-cmake"/*.AppImage "$ROOT/build-cmake"/*.appimage 2>/dev/null || true
    exit 1
fi

# Stable CRT names (drop CPack's Ship-<ver>-<distro-codename> naming).
APPIMAGE="$PACKAGES/$APPIMAGE_NAME"
if [ "$FOUND" != "$APPIMAGE" ]; then
    echo ">> Renaming $(basename "$FOUND") -> $APPIMAGE_NAME"
    mv -f "$FOUND" "$APPIMAGE"
fi
# Remove any leftover Ship-*.AppImage from earlier builds.
find "$PACKAGES" -maxdepth 1 -type f -iname 'Ship-*.AppImage' ! -samefile "$APPIMAGE" -delete 2>/dev/null || true
chmod +x "$APPIMAGE" 2>/dev/null || true

echo ">> Writing CRT sidecars next to $(basename "$APPIMAGE")..."
python3 - "$CONFIG_DIR/shipofharkinian.json" "$PACKAGES/shipofharkinian.json" "$FULLSCREEN" "${WIN_W:-}" "${WIN_H:-}" <<'PY'
import json, sys
src, dst, fullscreen, w, h = sys.argv[1:6]
data = json.loads(open(src, encoding="utf-8").read())
win = data.setdefault("Window", {})
fs = win.setdefault("Fullscreen", {})
fs["Enabled"] = fullscreen.lower() in ("1", "true", "yes")
if w and h:
    win["Width"] = int(w)
    win["Height"] = int(h)
else:
    win.pop("Width", None)
    win.pop("Height", None)
# Drop any leftover PC-only upscale key from older builds.
data.get("CVars", {}).get("gSettings", {}).pop("CrtOutputScale", None)
open(dst, "w", encoding="utf-8").write(json.dumps(data, indent=4) + "\n")
print(f"wrote {dst} (fullscreen={fs['Enabled']}, size={win.get('Width')}x{win.get('Height')})")
PY

command cp -f "$CONFIG_DIR/proggy-tiny.ttf" "$PACKAGES/"

echo
echo ">> Done."
ls -lah "$APPIMAGE" "$PACKAGES/shipofharkinian.json" "$PACKAGES/proggy-tiny.ttf"
echo "   Run from $PACKAGES with a legal OoT ROM beside the AppImage."
echo "   If FUSE is unavailable: APPIMAGE_EXTRACT_AND_RUN=1 ./$(basename "$APPIMAGE")"
