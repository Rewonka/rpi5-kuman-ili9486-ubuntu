# Kuman 3.5" SPI LCD on Raspberry Pi 5 — Ubuntu 26.04 LTS

Getting the Kuman SC11 3.5-inch SPI touchscreen working on a Raspberry Pi 5 running Ubuntu 26.04 LTS.

This project documents the installation process, troubleshooting, and a successfully tested Linux kernel driver patch.

## Project status

**Display: WORKING — tested on real hardware**

**Touchscreen: DETECTED — configuration in progress**

Tested configuration:

| Component | Details |
|---|---|
| Board | Raspberry Pi 5 |
| Display | Kuman SC11-3.5INCH-UK |
| LCD controller | ILI9486 |
| Touch controller | ADS7846 |
| Resolution | 480x320 |
| OS | Ubuntu 26.04.1 LTS |
| Kernel | 7.0.0-1020-raspi |
| Desktop | GNOME / Wayland |
| Display connection | GPIO / SPI |

## The problem

Ubuntu recognizes the ILI9486 SPI display, but its DRM driver reports an incorrect nominal refresh rate of approximately 0.007 Hz.

This caused severe GNOME desktop lag and long delays when loading the graphical session.

The issue was traced to the following display mode definition:

```c
DRM_SIMPLE_MODE(480, 320, 73, 49),
```

## The fix

The DRM display mode was changed to:

```c
DRM_MODE_INIT(30, 480, 320, 73, 49),
```

The patched ILI9486 driver was compiled as an external kernel module and installed without overwriting Ubuntu's original driver.

### Before

```text
mode: "480x320": 0 1 480 480 480 480 320 320 320 320 0x48 0x0
```

### After

```text
mode: "480x320": 30 4608 480 480 480 480 320 320 320 320 0x48 0x0
```

**Result:** The GNOME desktop became responsive, HDMI continued working normally, and the SPI LCD became usable as a secondary monitor.

Note: The reported 30 Hz DRM mode does not guarantee 30 actual frames per second over SPI.

## Boot configuration

The following settings were used in `/boot/firmware/config.txt`:

```ini
dtparam=spi=on
dtoverlay=vc4-kms-v3d

[all]
dtoverlay=piscreen,drm
```

Preserve the other Ubuntu boot settings.

## Documentation

- [How I Did It](docs/HOW-I-DID-IT.md) — Research and debugging journey.
- [Verified Setup](docs/VERIFIED-SETUP.md) — Tested hardware and driver information.
- [ILI9486 30 Hz Patch](patches/ili9486-30hz.patch) — Kernel driver modification.

## Installation

A reproducible installation script and detailed installation guide are in development.

The current patch has been successfully tested with Ubuntu kernel `7.0.0-1020-raspi`.

The module must be rebuilt for other kernel versions.

## Touchscreen

The ADS7846 touchscreen is detected by the Linux kernel.

Touch input currently affects the HDMI desktop rather than the SPI LCD. GNOME/Wayland touchscreen mapping and calibration are still being investigated.

## Work in progress

- Automated driver build and installation
- Driver rollback script
- ADS7846 touchscreen mapping
- Touch calibration
- SPI performance investigation

## Disclaimer

This is an experimental kernel driver modification.

Back up your system before installing custom kernel modules. The patch has only been verified on the hardware and kernel version listed above.

## License

License selection is pending.
