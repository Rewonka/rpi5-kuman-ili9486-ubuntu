#!/usr/bin/env bash
set -uo pipefail

echo "======================================"
echo " Raspberry Pi 5 - Kuman ILI9486"
echo " System Diagnostics"
echo "======================================"
echo

echo "=== Operating System ==="
grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
echo

echo "=== Kernel ==="
uname -r
uname -m
echo

echo "=== ILI9486 Driver ==="
if modinfo ili9486 >/dev/null 2>&1; then
    modinfo ili9486 | grep -E '^(filename|srcversion|vermagic):'
else
    echo "ILI9486 module not found"
fi
echo

echo "=== Currently Selected Module ==="
modprobe --show-depends ili9486 2>/dev/null | grep 'ili9486\.ko' \
    || echo "No module selected"
echo

echo "=== DRM Displays ==="
for connector in /sys/class/drm/card*-*/status; do
    [ -f "$connector" ] || continue
    printf '%s: ' "$(basename "$(dirname "$connector")")"
    cat "$connector"
done
echo

echo "=== SPI Display Modes ==="
for modes in /sys/class/drm/card*-SPI-*/modes; do
    [ -f "$modes" ] || continue
    echo "$modes"
    cat "$modes"
done
echo

echo "=== DRM 480x320 Mode ==="
found=0
for state in /sys/kernel/debug/dri/*/state; do
    [ -r "$state" ] || continue

    if grep -q 'mode: "480x320"' "$state"; then
        echo "DRM device: $state"
        grep 'mode: "480x320"' "$state"
        found=1
    fi
done

if [ "$found" -eq 0 ]; then
    echo "No active 480x320 DRM mode found (or debugfs unavailable)"
fi
echo

echo "=== Relevant Kernel Messages ==="
if dmesg >/dev/null 2>&1; then
    dmesg | grep -Ei 'ili9486|ads7846|piscreen' | tail -20 \
        || echo "No matching messages"
else
    echo "Kernel log requires elevated privileges"
fi

echo
echo "Diagnostics completed."
