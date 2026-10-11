#!/usr/bin/env bash
set -euo pipefail

KERNEL_VERSION="$(uname -r)"
MODULE_DIR="/lib/modules/${KERNEL_VERSION}/updates"
MODULE_PATH="${MODULE_DIR}/ili9486.ko"

echo "======================================"
echo " Kuman ILI9486 - Driver Rollback"
echo "======================================"
echo
echo "Kernel: ${KERNEL_VERSION}"
echo "Module: ${MODULE_PATH}"
echo

if [[ ! -f "${MODULE_PATH}" ]]; then
    echo "No custom ILI9486 module found."
    echo "Nothing to remove."
    exit 0
fi

echo "Custom driver detected."
echo

if [[ "${1:-}" != "--apply" ]]; then
    echo "DRY RUN - no changes made."
    echo
    echo "To restore the original Ubuntu driver, run:"
    echo "  sudo ./scripts/rollback.sh --apply"
    exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run with sudo."
    exit 1
fi

if [[ "${KERNEL_VERSION}" != *raspi* ]]; then
    echo "ERROR: This script is intended for Ubuntu Raspberry Pi kernels."
    exit 1
fi

echo "Removing custom ILI9486 module..."
rm -- "${MODULE_PATH}"

echo "Updating module dependency database..."
depmod -a "${KERNEL_VERSION}"

echo
echo "Selected ILI9486 module:"
modprobe --show-depends ili9486 | grep 'ili9486\.ko' || true

echo
echo "Rollback prepared successfully."
echo "Reboot manually to activate the original driver."
