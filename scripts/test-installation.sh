#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="$(uname -r)"

TEST_ROOT="$ROOT/build/test-modules"
SOURCE_MODULE="$ROOT/build/$KERNEL/ili9486/ili9486.ko"
DEST_DIR="$TEST_ROOT/$KERNEL/updates"
DEST_MODULE="$DEST_DIR/ili9486.ko"
DEST_CHECKSUM="$DEST_MODULE.sha256"

echo "======================================"
echo " Kuman ILI9486 - Integration Test"
echo "======================================"
echo

if [[ "$EUID" -eq 0 ]]; then
    echo "ERROR: Do not run this test with sudo."
    exit 1
fi

if [[ ! -f "$SOURCE_MODULE" ]]; then
    echo "ERROR: Compiled module not found:"
    echo "$SOURCE_MODULE"
    echo
    echo "Run ./scripts/install.sh first."
    exit 1
fi

source "$ROOT/scripts/lib/safety.sh"
MODULES_ROOT="$TEST_ROOT"

validate_modules_root
validate_module_path "$KERNEL"

if [[ -e "$DEST_MODULE" || -L "$DEST_MODULE" ||
      -e "$DEST_CHECKSUM" || -L "$DEST_CHECKSUM" ]]; then
    echo "ERROR: Test destination already contains module files."
    echo "Refusing to overwrite existing test data."
    exit 1
fi

echo "=== 1. Test installation ==="

MODULES_ROOT="$TEST_ROOT" \
    "$ROOT/scripts/install.sh" --install

echo
echo "=== 2. Verify installed module ==="

[[ -f "$DEST_MODULE" ]] || {
    echo "FAIL: Module was not installed."
    exit 1
}

[[ -f "$DEST_CHECKSUM" ]] || {
    echo "FAIL: Checksum file was not created."
    exit 1
}

EXPECTED="$(cat "$DEST_CHECKSUM")"
ACTUAL="$(sha256sum "$DEST_MODULE" | awk '{print $1}')"

[[ "$EXPECTED" == "$ACTUAL" ]] || {
    echo "FAIL: SHA-256 mismatch."
    exit 1
}

echo "PASS: Installed module checksum verified."

echo
echo "=== 3. Test rollback preview ==="

MODULES_ROOT="$TEST_ROOT" \
    "$ROOT/scripts/rollback.sh"

[[ -f "$DEST_MODULE" ]] || {
    echo "FAIL: Dry run unexpectedly removed the module."
    exit 1
}

echo "PASS: Dry run preserved the installed module."

echo
echo "=== 4. Test rollback ==="

MODULES_ROOT="$TEST_ROOT" \
    "$ROOT/scripts/rollback.sh" --apply

echo
echo "=== 5. Verify cleanup ==="

if [[ -e "$DEST_MODULE" || -e "$DEST_CHECKSUM" ]]; then
    echo "FAIL: Test module files were not removed."
    exit 1
fi

echo "PASS: Test module files removed."

echo
echo "======================================"
echo " ALL INTEGRATION TESTS PASSED"
echo "======================================"
