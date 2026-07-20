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

```bash
git clone --recursive https://github.com/gustavostuff/Shipwright-CRT.git
cd Shipwright-CRT
./scripts/linux/appimage/build.sh
```

Works on **x86_64 PC** and **aarch64 Pi** (linuxdeploy is selected for the host arch). This is a **native** build only: there is no cross-compile from a PC to the Pi.

Use `HOST_TARGET` to pick the sidecar config written next to the AppImage:

```bash
# Develop / test on a normal Linux PC (windowed 320x240), no CRT or Pi required.
# Handy for trying menu changes and other fork tweaks.
HOST_TARGET=pc ./scripts/linux/appimage/build.sh

# Build on the Pi itself (e.g. over an SSH session). Not a PC cross-build.
# Produces the fullscreen CRT / Pi AppImage.
HOST_TARGET=pi ./scripts/linux/appimage/build.sh
```

If `HOST_TARGET` is omitted, Pi arches (`aarch64` / `arm64`) default to `pi`, otherwise `pc`. On a PC use `HOST_TARGET=pc` (or the default) to iterate on the UI. When you are ready for glass, clone or sync the tree onto the Pi and run `HOST_TARGET=pi` there.

Output lands in `_packages/`:

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
