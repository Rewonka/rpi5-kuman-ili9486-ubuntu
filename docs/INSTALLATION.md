# Installation Guide

## Hardware

- Raspberry Pi 5
- Kuman SC11 3.5-inch SPI LCD
- ILI9486 display controller
- ADS7846 resistive touchscreen
- 480x320 resolution

## Tested environment

- Ubuntu 26.04.1 LTS
- Kernel: 7.0.0-1020-raspi
- ARM64
- GNOME / Wayland

The display and 30 Hz DRM patch have been verified on real hardware.

Touchscreen mapping is not yet complete.

## 1. Enable the SPI display

Back up the boot configuration:

```bash
sudo cp /boot/firmware/config.txt /boot/firmware/config.txt.before-kuman
```

Edit:

```bash
sudo nano /boot/firmware/config.txt
```

Ensure that SPI and the KMS graphics driver are enabled:

```ini
dtparam=spi=on
dtoverlay=vc4-kms-v3d
```

Enable the PiScreen DRM overlay in the final `[all]` section:

```ini
[all]
dtoverlay=piscreen,drm
```

Preserve the other Ubuntu boot settings.

Reboot:

```bash
sudo reboot
```

## 2. Verify hardware detection

```bash
modinfo ili9486
```

```bash
sudo dmesg | grep -Ei 'ili9486|ads7846|piscreen|spi0'
```

```bash
ls /sys/class/drm/
```

The SPI display should appear as a connector such as:

```text
card1-SPI-1
```

DRM card numbering may differ.

## 3. The refresh-rate problem

The original ILI9486 driver may report approximately
0.007 Hz as its nominal DRM refresh rate.

This was associated with severe GNOME desktop stalls
in the tested environment.

The patch replaces:

```c
DRM_SIMPLE_MODE(480, 320, 73, 49),
```

with:

```c
DRM_MODE_INIT(30, 480, 320, 73, 49),
```

This corrects the nominal DRM mode timing.

It does not guarantee 30 actual FPS over SPI.

## 4. Install build dependencies

Install the tools required to compile a kernel module:

```bash
sudo apt install git build-essential gcc-15 \
  linux-headers-$(uname -r)
```

The matching Ubuntu kernel source must also be available.

For Ubuntu 26.04, source repositories may need to be enabled.

See [How I Did It](HOW-I-DID-IT.md) for the tested
source-package retrieval procedure.

## 5. Clone the repository

```bash
git clone https://github.com/Rewonka/rpi5-kuman-ili9486-ubuntu.git
cd rpi5-kuman-ili9486-ubuntu
```

## 6. Build the patched driver

```bash
./scripts/install.sh
```

The script:

1. Identifies the running kernel.
2. Determines the matching Ubuntu source version.
3. Downloads the source package.
4. Applies the 30 Hz patch.
5. Builds an external ILI9486 module.

The build mode does not install the module.

**Test status:** Successfully tested with kernel
`7.0.0-1020-raspi`.

## 7. Install the compiled module

```bash
sudo ./scripts/install.sh --install
```

The patched module is installed into:

```text
/lib/modules/<kernel-version>/updates/ili9486.ko
```

Ubuntu's original module is not overwritten.

**Test status:** Manual installation has been verified.
The script's installation mode has been tested for
refusing to overwrite an existing module, but a clean
installation through this script has not yet been tested.

Reboot manually after installation.

## 8. Verify the result

```bash
sudo ./scripts/diagnose.sh
```

A successful patched configuration should report a
nominal 30 Hz mode for the SPI display.

The tested system reported:

```text
mode: "480x320": 30 4608 480 480 480 480 320 320 320 320 0x48 0x0
```

## 9. Rollback

Preview the rollback operation:

```bash
./scripts/rollback.sh
```

To remove the custom module:

```bash
sudo ./scripts/rollback.sh --apply
```

Then reboot manually.

**Test status:** The rollback preview has been tested.
The actual removal operation has not yet been tested.

## Known limitations

- The patch was verified with Ubuntu kernel 7.0.0-1020-raspi.
- Custom kernel modules may require rebuilding after kernel upgrades.
- The custom module is unsigned and may be rejected by
  systems enforcing module signatures.
- GNOME window movement on the SPI display can still lag.
- ADS7846 touchscreen mapping remains unfinished.
- Automated installation and rollback require further testing.

## Troubleshooting

Run:

```bash
sudo ./scripts/diagnose.sh
```

For the full investigation and original diagnostic commands,
see [How I Did It](HOW-I-DID-IT.md).
