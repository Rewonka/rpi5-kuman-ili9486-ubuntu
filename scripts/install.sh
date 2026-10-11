#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="$(uname -r)"
BUILD_DIR="$ROOT/build"
WORK_DIR="$BUILD_DIR/kernel-source"
DRIVER_DIR="$BUILD_DIR/$KERNEL/ili9486"
PATCH_FILE="$ROOT/patches/ili9486-30hz.patch"
MODULE="$DRIVER_DIR/ili9486.ko"
MODULES_ROOT="${MODULES_ROOT:-/lib/modules}"
DEST="${MODULES_ROOT}/${KERNEL}/updates/ili9486.ko"

usage() {
    echo "Usage:"
    echo "  $0             Download, patch and build"
    echo "  sudo $0 --install   Install previously built module"
    echo
    echo "The script does not reboot automatically."
}

check_kernel() {
    [[ "$KERNEL" == *-raspi ]] || {
        echo "ERROR: Unsupported kernel: $KERNEL"
        exit 1
    }

    [[ "$(uname -m)" == "aarch64" ]] || {
        echo "ERROR: ARM64 kernel required."
        exit 1
    }

    [[ -d "/lib/modules/$KERNEL/build" ]] || {
        echo "ERROR: Matching kernel headers are missing."
        echo "Install: linux-headers-$KERNEL"
        exit 1
    }
}

kernel_source_version() {
    local package="linux-image-$KERNEL"
    local source_name

    dpkg-query -W "$package" >/dev/null 2>&1 || {
        echo "ERROR: Running kernel package not found: $package" >&2
        return 1
    }

    source_name="$(apt-cache show "$package" |
        sed -n 's/^Source: //p' | head -1)"

    [[ "$source_name" == "linux-raspi" ]] || {
        echo "ERROR: Unexpected kernel source package: $source_name" >&2
        return 1
    }

    dpkg-query -W -f='${Version}' "$package"
}

build_module() {
    check_kernel

    for command in git make gcc patch dpkg-source apt-get modinfo; do
        command -v "$command" >/dev/null || {
            echo "ERROR: Missing command: $command"
            exit 1
        }
    done

    local version
    version="$(kernel_source_version)"

    echo "======================================"
    echo " Kuman ILI9486 - Build"
    echo "======================================"
    echo "Kernel: $KERNEL"
    echo "Source: linux-raspi $version"
    echo

    mkdir -p "$WORK_DIR" "$DRIVER_DIR"

    cd "$WORK_DIR"

    if [[ ! -f "linux-raspi_${version}.dsc" ]]; then
        echo "Downloading Ubuntu kernel source..."

        apt-get source --only-source --download-only \
            "linux-raspi=$version"
    fi

    local source_dir="$WORK_DIR/linux-raspi-7.0.0"

    # Find source directory name from the source package metadata.
    local dsc="$WORK_DIR/linux-raspi_${version}.dsc"
    [[ -f "$dsc" ]] || {
        echo "ERROR: Source package download incomplete."
        exit 1
    }

    local source_basename
    source_basename="$(dpkg-source --print-format "$dsc" 2>/dev/null || true)"

    # Extract into a controlled directory independent of source naming.
    source_dir="$WORK_DIR/extracted"

    if [[ ! -d "$source_dir" ]]; then
        echo "Extracting Ubuntu kernel source..."
        dpkg-source -x "$dsc" "$source_dir"
    fi

    local source_file="$source_dir/drivers/gpu/drm/tiny/ili9486.c"

    [[ -f "$source_file" ]] || {
        echo "ERROR: ILI9486 source file not found."
        exit 1
    }

    echo "Checking patch..."

    if grep -q 'DRM_MODE_INIT(30, 480, 320, 73, 49)' "$source_file"; then
        echo "Patch already applied."
    else
        patch --dry-run -d "$source_dir" -p1 < "$PATCH_FILE"
        patch -d "$source_dir" -p1 < "$PATCH_FILE"
    fi

    echo "Preparing external module..."
    cp "$source_file" "$DRIVER_DIR/ili9486.c"

    cat > "$DRIVER_DIR/Makefile" <<'MAKEFILE'
obj-m += ili9486.o

KDIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
MAKEFILE

    echo "Compiling..."
    make -C "$DRIVER_DIR"

    [[ -f "$MODULE" ]] || {
        echo "ERROR: Module build failed."
        exit 1
    }

    echo
    echo "Built module:"
    modinfo "$MODULE" | grep -E '^(filename|srcversion|vermagic):'

    echo
    echo "Build completed."
    echo "The running system was not modified."
    echo
    echo "To install:"
    echo "  sudo ./scripts/install.sh --install"
}

install_module() {
    source "$ROOT/scripts/lib/safety.sh"
    validate_modules_root || exit 1
    validate_module_path "$KERNEL" || exit 1

    local test_mode="$TEST_MODE"

    if [[ "$test_mode" -eq 0 && "$EUID" -ne 0 ]]; then
        echo "ERROR: Installation requires sudo."
        exit 1
    fi

    if [[ "$test_mode" -eq 1 && "$EUID" -eq 0 ]]; then
        echo "ERROR: Test installation must run without sudo."
        exit 1
    fi

    check_kernel

    [[ -f "$MODULE" ]] || {
        echo "ERROR: No built module found."
        echo "Run ./scripts/install.sh first."
        exit 1
    }

    local vermagic
    vermagic="$(modinfo -F vermagic "$MODULE")"

    [[ "$vermagic" == "$KERNEL "* ]] || {
        echo "ERROR: Module was built for a different kernel."
        exit 1
    }

    [[ ! -e "$DEST" ]] || {
        echo "ERROR: A custom module already exists:"
        echo "$DEST"
        echo "Refusing to overwrite it."
        exit 1
    }

    echo "Installing patched ILI9486 module..."

    local checksum_path="${DEST}.sha256"
    local checksum

    checksum="$(sha256sum "$MODULE" | awk '{print $1}')"

    install -D -m 644 "$MODULE" "$DEST"

    if ! printf '%s\n' "$checksum" > "$checksum_path"; then
        echo "ERROR: Failed to write module checksum." >&2
        rm -f -- "$DEST" "$checksum_path"

        if [[ "$test_mode" -eq 0 ]]; then
            depmod -a "$KERNEL"
        fi

        exit 1
    fi

    if [[ "$test_mode" -eq 0 ]]; then
        depmod -a "$KERNEL"
    else
        echo "TEST MODE: Skipping depmod."
    fi

    echo
    if [[ "$test_mode" -eq 0 ]]; then
        echo "Selected module:"
        modprobe --show-depends ili9486 | grep 'ili9486\.ko' || true
    else
        echo "TEST MODE: Module installed into test directory."
        echo "Path: $DEST"
    fi

    echo
    echo "Installation completed."
    echo "Reboot manually to activate the driver."
}

case "${1:-}" in
    "")
        [[ "$EUID" -ne 0 ]] || {
            echo "ERROR: Run the build without sudo."
            exit 1
        }
        build_module
        ;;
    --install)
        install_module
        ;;
    --help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
