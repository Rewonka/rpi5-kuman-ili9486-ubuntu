# How I Did It: Kuman 3.5-inch SPI LCD on Raspberry Pi 5

> **Status:** Work in progress. Display and touchscreen are detected on Ubuntu 26.04.1 LTS, but GNOME is slow and the proposed 30 Hz DRM mode patch has **not yet been compiled or validated**.

## Hardware and environment

- Raspberry Pi 5
- Kuman SC11-3.5INCH-UK, 3.5-inch 480×320 SPI TFT
- ILI9486 display controller and ADS7846 resistive touch controller
- Ubuntu 26.04.1 LTS (Resolute Raccoon), ARM64
- Kernel: `7.0.0-1020-raspi` (`linux-raspi` source version `7.0.0-1020.20`)
- GNOME desktop (Mutter compositor); HDMI monitor also connected

## 1. Initial setup

I enabled SPI and the DRM-based `piscreen` overlay in `/boot/firmware/config.txt`:

```ini
dtparam=spi=on
dtoverlay=vc4-kms-v3d

[all]
dtoverlay=piscreen,drm
```

**Important:** Preserve existing Ubuntu settings, including `os_prefix`, kernel/initramfs settings, and board-specific sections. Back up `config.txt` before editing.

The overlay was present at `/boot/firmware/current/overlays/piscreen.dtbo` and the driver was available as a module (`modinfo ili9486`).

## 2. What worked and what broke

The small LCD showed boot graphics. Once GNOME started, the display was black at times, and the login/desktop took unusually long to appear. Switching to a text TTY and back sometimes restored the HDMI login screen.

Kernel logs showed both controllers detected:

```text
ads7846 spi0.1: touchscreen, irq 168
[drm] Initialized ili9486 1.0.0 for spi0.0 on minor 1
ili9486 spi0.0: [drm] fb1: ili9486drmfb frame buffer device
```

The display appeared as `/sys/class/drm/card1-SPI-1` and reported the mode `480x320`. The GNOME compositor allocated a 480×320 framebuffer for the SPI display. **This establishes driver initialization, not a working desktop experience.**

## 3. The key clue: implausible DRM mode timing

I inspected the active DRM state:

```bash
sudo mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
sudo cat /sys/kernel/debug/dri/1/state | grep -A 20 -B 5 '480x320'
```

The display mode included:

```text
mode: "480x320": 0 1 480 480 480 480 320 320 320 320 0x48 0x0
```

The pixel clock is represented as **1 kHz**. With 480×320 total pixels, that implies approximately `1000 / (480 × 320) = 0.00651 Hz` as a reported refresh rate. On an earlier Raspberry Pi OS setup, the same LCD was advertised at approximately `0.007 Hz` by `wlr-randr`.

**Hypothesis:** This nonsensical *reported* refresh rate may contribute to compositor stalls and window-update problems. This is **not** a measurement of the actual SPI transfer rate or achievable FPS, and causation has not yet been proven.

## 4. Find the exact Ubuntu kernel source

The matching headers were available and installed:

```bash
sudo apt install linux-headers-7.0.0-1020-raspi
ls -ld /lib/modules/$(uname -r)/build
```

The running kernel was compiled with GCC 15.2.0, so I installed a matching GCC toolchain.

I enabled `deb-src` for the Ubuntu `resolute` and `resolute-updates` suites, then inspected:

```bash
apt-cache showsrc linux-raspi
```

**Pitfall:** `apt-get source --download-only linux-raspi=7.0.0-1020.20` picked **`linux-meta-raspi`**, the small metapackage source. The solution was:

```bash
apt-get source --only-source --download-only linux-raspi=7.0.0-1020.20
```

This fetched the actual kernel source archives, about 262 MB in total. These downloaded archives are local build inputs and **must not be committed** to the repository.

The base source archive contains `linux-7.0/drivers/gpu/drm/tiny/ili9486.c`.

## 5. Find the mode definition

Inspecting just this file without extracting the full archive:

```bash
tar -xOzf linux-raspi_7.0.0.orig.tar.gz \
  linux-7.0/drivers/gpu/drm/tiny/ili9486.c \
  | grep -n -A 12 -B 8 'DRM_SIMPLE_MODE\|DRM_MODE_INIT'
```

The file defines:

```c
static const struct drm_display_mode waveshare_mode = {
    DRM_SIMPLE_MODE(480, 320, 73, 49),
};
```

The Ubuntu source-package diff also changes this file, removing an `ili9486` entry from its SPI device ID table. This Ubuntu-specific change must be preserved.

## 6. Candidate patch — not yet validated

The proposed change is:

```diff
-    DRM_SIMPLE_MODE(480, 320, 73, 49),
+    DRM_MODE_INIT(30, 480, 320, 73, 49),
```

The initial patch was saved at `patches/ili9486-30hz.patch`. It has **not yet been tested against the fully reconstructed Ubuntu source package**, compiled, installed, or measured in GNOME. The `30` is a **nominal DRM refresh value**, **not** a promise of 30 physical frames per second.

## 7. Next steps

1. Reconstruct the full Ubuntu source including its `.diff.gz` changes.
2. Dry-run the patch against that source.
3. Compile a test module for exactly the running kernel and check its metadata.
4. Prepare a safe rollback method before testing the replacement.
5. Measure reported refresh rate, GNOME responsiveness, actual FPS/transfer performance, and touchscreen behavior.
6. Only then label the patch a verified fix.

## Useful diagnostic commands

```bash
cat /etc/os-release
uname -a
modinfo ili9486 | grep -E 'filename|vermagic|description'
ls /sys/class/drm/
cat /sys/class/drm/card1-SPI-1/status
cat /sys/class/drm/card1-SPI-1/modes
sudo dmesg | grep -Ei 'ili9486|piscreen|ads7846|spi0|drm' | tail -60
sudo cat /sys/kernel/debug/dri/1/state | grep -A 20 -B 5 '480x320'
```

> DRM card/minor numbering is not guaranteed. Check `/sys/class/drm/` and `dmesg` on your own device; do not assume `card1` or `/dri/1`.
