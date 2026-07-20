# Shipwright-CRT
===============

A fork of [Ship of Harkinian](https://github.com/HarbourMasters/Shipwright) aimed at **320x240 CRT** play on Raspberry Pi Linux (specifically Debian-family images such as RGB-Pi), with a small controller-friendly settings UI.

## What you get

- Simplified CRT menu (not the full upstream SoH settings UI)
- Auto ROM to `oot.o2r` extraction on first launch
- AppImage packages that embed `soh.o2r` and extractor `assets/`

You still need a **legally obtained** Ocarina of Time ROM (`.z64` / `.n64` / `.v64`).

## CRT settings UI

Upstream SoH has a large desktop-oriented menu. This fork uses a compact modal meant for a CRT and a gamepad (keyboard and mouse are still supported though). The CRT UI is **English-only for now**. Several settings UI controls will not be migrated, I'll try to keep it simple. For the full SoH feature set, see [Harbour Masters](https://github.com/HarbourMasters/Shipwright).

## Build (AppImage)

### PC

```bash
git clone --recursive https://github.com/gustavostuff/Shipwright-CRT.git
cd Shipwright-CRT
HOST_TARGET=pc ./scripts/linux/appimage/build.sh
```

### Raspberry Pi

The Pi rootfs is usually too small to clone and compile. **Do not** `git clone` into `/home/pi`. Instead, keep an ext4 loop image (default `/media/sd/soh-build.img`), and let the build script mount it, clone onto it, and build there:

```bash
# One-time: free a failed rootfs clone if you already hit "No space left on device"
rm -rf ~/Shipwright-CRT

# Bootstrap the build script (no full tree on the rootfs)
curl -fsSL https://raw.githubusercontent.com/gustavostuff/Shipwright-CRT/main/scripts/linux/appimage/build.sh \
  -o /tmp/soh-crt-build.sh
chmod +x /tmp/soh-crt-build.sh

# Mounts ~/soh-build, clones into ~/soh-build/Shipwright-CRT, then builds
HOST_TARGET=pi /tmp/soh-crt-build.sh
# Optional non-interactive sudo for the loop mount:
# SUDO_PWD='yourpassword' HOST_TARGET=pi /tmp/soh-crt-build.sh
```

Later rebuilds (tree already on the image):

```bash
HOST_TARGET=pi ~/soh-build/Shipwright-CRT/scripts/linux/appimage/build.sh
```

Overrides: `SOH_BUILD_IMG`, `SOH_BUILD_MOUNT`, `SOH_BUILD_TREE`, `SOH_GIT_URL`, `SUDO_PWD`.

This is a **native** build only (no PC→Pi cross-compile). If `HOST_TARGET` is omitted, Pi arches default to `pi`, otherwise `pc`.

Output lands in `_packages/` (on the Pi that is under the mounted tree):

| Target | AppImage |
|--------|----------|
| `pc` (default on x86_64) | `soh-pc.AppImage` |
| `pi` (default on aarch64) | `soh-raspberry-pi.AppImage` |

Plus `shipofharkinian.json` and `proggy-tiny.ttf` beside it.

## Run

```bash
cd _packages
# put your OoT ROM in this folder
chmod +x soh-pc.AppImage   # or soh-raspberry-pi.AppImage
./soh-pc.AppImage
```

If the AppImage cannot mount (common without FUSE):

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./soh-pc.AppImage
```

First launch extracts `oot.o2r` beside the AppImage. There is no external `assets/` folder.

## License / upstream

Follows Ship of Harkinian / Harbour Masters terms. Do not redistribute copyrighted ROMs.
