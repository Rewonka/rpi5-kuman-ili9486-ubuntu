#!/usr/bin/env bash

# Shared safety checks for ILI9486 installation and rollback.
# Requires ROOT, MODULES_ROOT and the running kernel version.

check_no_symlinks() {
    local path="$1"
    local current=""
    local component
    local -a components

    [[ "$path" == /* ]] || {
        echo "ERROR: Path must be absolute: $path" >&2
        return 1
    }

    IFS='/' read -r -a components <<< "${path#/}"

    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue

        if [[ "$component" == "." || "$component" == ".." ]]; then
            echo "ERROR: Unsafe path component: $component" >&2
            return 1
        fi

        current="$current/$component"

        if [[ -L "$current" ]]; then
            echo "ERROR: Symlink detected: $current" >&2
            return 1
        fi
    done
}

validate_modules_root() {
    local expected_test_root="$ROOT/build/test-modules"
    local requested_root="$MODULES_ROOT"

    TEST_MODE=0

    if [[ "$requested_root" == "/lib/modules" ]]; then
        return 0
    fi

    if [[ "$requested_root" != "$expected_test_root" ]]; then
        echo "ERROR: Unsupported MODULES_ROOT: $requested_root" >&2
        return 1
    fi

    check_no_symlinks "$requested_root" || return 1

    TEST_MODE=1
}

validate_module_path() {
    local kernel="$1"
    local module_dir="$MODULES_ROOT/$kernel/updates"

    if [[ "$TEST_MODE" -eq 1 ]]; then
        check_no_symlinks "$module_dir" || return 1
        check_no_symlinks "$module_dir/ili9486.ko" || return 1
        check_no_symlinks "$module_dir/ili9486.ko.sha256" || return 1
    fi
}
