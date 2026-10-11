#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="$(uname -r)"
MODULES_ROOT="${MODULES_ROOT:-/lib/modules}"
MODULE_DIR="${MODULES_ROOT}/${KERNEL_VERSION}/updates"
MODULE_PATH="${MODULE_DIR}/ili9486.ko"
CHECKSUM_PATH="${MODULE_DIR}/ili9486.ko.sha256"

echo "======================================"
echo " Kuman ILI9486 - Driver Rollback"
echo "======================================"
echo
echo "Kernel: ${KERNEL_VERSION}"
echo "Module: ${MODULE_PATH}"
echo

source "$ROOT/scripts/lib/safety.sh"
validate_modules_root || exit 1
validate_module_path "$KERNEL_VERSION" || exit 1

if [[ ! -f "${MODULE_PATH}" ]]; then
    echo "No custom ILI9486 module found."
    echo "Nothing to remove."
    exit 0
fi

echo "Custom driver detected."
echo

if [[ ! -f "${CHECKSUM_PATH}" ]]; then
    echo "ERROR: Installation checksum is missing."
    echo "Refusing to remove a module of unknown origin."
    exit 1
fi

EXPECTED="$(cat "${CHECKSUM_PATH}")"
ACTUAL="$(sha256sum "${MODULE_PATH}" | awk '{print $1}')"

if [[ "${EXPECTED}" != "${ACTUAL}" ]]; then
    echo "ERROR: Module checksum mismatch."
    echo "Refusing to remove a modified or unknown module."
    exit 1
fi

echo "Module checksum verified."
echo



if [[ "${1:-}" != "--apply" ]]; then
    echo "DRY RUN - no changes made."
    echo
    echo "To restore the original Ubuntu driver, run:"
    echo "  sudo ./scripts/rollback.sh --apply"
    exit 0
fi

if [[ "$TEST_MODE" -eq 0 && "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run with sudo."
    exit 1
fi

if [[ "$TEST_MODE" -eq 1 && "${EUID}" -eq 0 ]]; then
    echo "ERROR: Test rollback must run without sudo."
    exit 1
fi

if [[ "${KERNEL_VERSION}" != *raspi* ]]; then
    echo "ERROR: This script is intended for Ubuntu Raspberry Pi kernels."
    exit 1
fi

echo "Removing custom ILI9486 module..."
rm -- "${MODULE_PATH}" "${CHECKSUM_PATH}"

echo "Updating module dependency database..."
if [[ "$TEST_MODE" -eq 0 ]]; then
    depmod -a "${KERNEL_VERSION}"
else
    echo "TEST MODE: Skipping depmod."
fi

echo
echo "Selected ILI9486 module:"
if [[ "$TEST_MODE" -eq 0 ]]; then
    modprobe --show-depends ili9486 | grep 'ili9486\.ko' || true
else
    echo "TEST MODE: No system module lookup performed."
fi

echo
echo "Rollback prepared successfully."
echo "Reboot manually to activate the original driver."
