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
#   curl -fsSL https://raw.githubusercontent.com/gustavostuff/Shipwright-CRT/develop/scripts/linux/appimage/build.sh \
#     -o /tmp/soh-crt-build.sh && chmod +x /tmp/soh-crt-build.sh
#   HOST_TARGET=pi /tmp/soh-crt-build.sh
#   # or, if already on the image checkout:
#   HOST_TARGET=pi ./scripts/linux/appimage/build.sh
#
# Native build only: no PC -> Pi cross-compile. If HOST_TARGET is unset,
# aarch64/arm64 => pi, otherwise => pc.
#
# Pi env overrides:
#   SOH_BUILD_IMG       loop image (default /media/sd/soh-build.img; created if missing)
#   SOH_BUILD_IMG_SIZE  size when creating (default 8G)
#   SOH_BUILD_MOUNT     mount point (default ~/soh-build)
#   SOH_BUILD_TREE      clone/build dir (default $SOH_BUILD_MOUNT/Shipwright-CRT)
#   SOH_GIT_URL         clone URL (default github.com/gustavostuff/Shipwright-CRT.git)
#   SUDO_PWD            piped to sudo -S for the loop mount (no prompt)
#
# Output (under _packages/):
#   HOST_TARGET=pc  -> build-linux-x86_64/soh-pc.AppImage + soh-pc-<CRT_VERSION>.zip
#   HOST_TARGET=pi  -> build-linux-arm64/soh-raspberry-pi.AppImage + soh-raspberry-pi-<CRT_VERSION>.zip
#   Zip holds the AppImage (stable name), shipofharkinian.json, and Proggy Tiny files.
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
        APPIMAGE_BASENAME="soh-pc"
        APPIMAGE_NAME="soh-pc.AppImage"
        PACKAGE_DIR="build-linux-x86_64"
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
        APPIMAGE_BASENAME="soh-raspberry-pi"
        APPIMAGE_NAME="soh-raspberry-pi.AppImage"
        PACKAGE_DIR="build-linux-arm64"

        # Rootfs is too small for clone+build. Use a loop-mounted ext4 image
        # (created automatically if missing -- that can take a while on SD).
        IMG="${SOH_BUILD_IMG:-/media/sd/soh-build.img}"
        MOUNT="${SOH_BUILD_MOUNT:-$HOME/soh-build}"
        TREE="${SOH_BUILD_TREE:-$MOUNT/Shipwright-CRT}"
        GIT_URL="${SOH_GIT_URL:-https://github.com/gustavostuff/Shipwright-CRT.git}"

        ENSURE_SCRIPT=""
        if [ -n "$INVOKED_ROOT" ] && [ -f "$INVOKED_ROOT/scripts/linux/ensure-pi-build-img.sh" ]; then
            ENSURE_SCRIPT="$INVOKED_ROOT/scripts/linux/ensure-pi-build-img.sh"
        elif [ -f "$SCRIPT_DIR/../ensure-pi-build-img.sh" ]; then
            ENSURE_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/ensure-pi-build-img.sh"
        fi
        if [ -n "$ENSURE_SCRIPT" ]; then
            # shellcheck disable=SC1090
            bash "$ENSURE_SCRIPT"
        else
            echo "ERROR: cannot find scripts/linux/ensure-pi-build-img.sh" >&2
            exit 1
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
# CPack still drops into _packages/; final CRT artifacts go in the arch folder.
PACKAGES_ROOT="$ROOT/_packages"
PACKAGES="$PACKAGES_ROOT/$PACKAGE_DIR"

# CRT fork version only (not upstream SoH). See CRT_VERSION at repo root.
if [ ! -f "$ROOT/CRT_VERSION" ]; then
    echo "ERROR: missing $ROOT/CRT_VERSION" >&2
    exit 1
fi
CRT_VERSION="$(tr -d '[:space:]' < "$ROOT/CRT_VERSION")"
if [ -z "$CRT_VERSION" ]; then
    echo "ERROR: CRT_VERSION is empty" >&2
    exit 1
fi
RELEASE_ZIP="${APPIMAGE_BASENAME}-${CRT_VERSION}.zip"

echo ">> Shipwright-CRT AppImage build (HOST_TARGET=$HOST_TARGET, arch=$HOST_ARCH, CRT_VERSION=$CRT_VERSION)"
echo ">> Tree: $ROOT"
echo ">> Package dir: $PACKAGES"
echo ">> AppImage: $APPIMAGE_NAME"
echo ">> Release zip: $RELEASE_ZIP"

if [ ! -f "$ROOT/libultraship/CMakeLists.txt" ]; then
    echo ">> Initializing submodules..."
    git submodule update --init --recursive
fi

for t in cmake ninja git python3 zip; do
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
mkdir -p "$PACKAGES_ROOT" "$PACKAGES"
(cd "$ROOT/build-cmake" && cpack -G External)

# CPack also writes a Ship-*-*.json metadata stub; not part of the CRT runtime.
rm -f "$PACKAGES_ROOT"/Ship-*.json

# Prefer _packages/ (CPack output). Fall back to build-cmake if linuxdeploy used a
# relative OUTPUT (legacy Packaging.cmake: Ship-*.appimage next to the build tree).
pick_appimage() {
    local dir="$1"
    find "$dir" -maxdepth 1 -type f \( -iname '*.AppImage' \) ! -iname 'linuxdeploy*' \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-
}

FOUND="$(pick_appimage "$PACKAGES_ROOT" || true)"
if [ -z "$FOUND" ] || [ ! -f "$FOUND" ]; then
    FOUND="$(pick_appimage "$PACKAGES" || true)"
fi
if [ -z "$FOUND" ] || [ ! -f "$FOUND" ]; then
    FALLBACK="$(pick_appimage "$ROOT/build-cmake" || true)"
    if [ -n "$FALLBACK" ] && [ -f "$FALLBACK" ]; then
        echo ">> Found $(basename "$FALLBACK") under build-cmake"
        FOUND="$FALLBACK"
    fi
fi
if [ -z "$FOUND" ] || [ ! -f "$FOUND" ]; then
    echo "ERROR: no AppImage found under $PACKAGES_ROOT (or build-cmake/)" >&2
    ls -la "$PACKAGES_ROOT" "$ROOT/build-cmake"/*.AppImage "$ROOT/build-cmake"/*.appimage 2>/dev/null || true
    exit 1
fi

# Stable CRT names in the arch folder (drop CPack's Ship-<ver>-<distro> naming).
APPIMAGE="$PACKAGES/$APPIMAGE_NAME"
if [ "$FOUND" != "$APPIMAGE" ]; then
    echo ">> Placing $(basename "$FOUND") -> $PACKAGE_DIR/$APPIMAGE_NAME"
    mv -f "$FOUND" "$APPIMAGE"
fi
# Remove any leftover Ship-*.AppImage from earlier builds (root or arch folder).
find "$PACKAGES_ROOT" "$PACKAGES" -maxdepth 1 -type f -iname 'Ship-*.AppImage' \
    ! -samefile "$APPIMAGE" -delete 2>/dev/null || true
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
command cp -f "$CONFIG_DIR/proggy-tiny-licence.txt" "$PACKAGES/"

echo ">> Creating release zip $RELEASE_ZIP ..."
# Drop prior CRT release zips in this package dir so only the current version remains.
find "$PACKAGES" -maxdepth 1 -type f -name "${APPIMAGE_BASENAME}-*.zip" -delete 2>/dev/null || true
(
    cd "$PACKAGES"
    zip -9 "$RELEASE_ZIP" \
        "$APPIMAGE_NAME" \
        shipofharkinian.json \
        proggy-tiny.ttf \
        proggy-tiny-licence.txt
)

echo
echo ">> Done."
ls -lah "$PACKAGES"
echo "   Release zip: $PACKAGES/$RELEASE_ZIP"
echo "   Run from $PACKAGES with a legal OoT ROM beside the AppImage."
echo "   If FUSE is unavailable: APPIMAGE_EXTRACT_AND_RUN=1 ./$(basename "$APPIMAGE")"
