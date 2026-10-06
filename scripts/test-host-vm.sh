#!/bin/sh
# EM-1: build, sign and run the native host executable-memory probe.
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo 'ERROR: run natively on Apple Silicon macOS.' >&2
    exit 1
fi
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/aoe2-host-vm.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
printf 'Host: macOS %s (%s)\nSDK: %s\n' "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)" "$(xcrun --show-sdk-version)"
# Same layout and signature as the passing P0 probe and the Wine loader.
xcrun clang -arch arm64 -mmacosx-version-min=26.5 -Wall -Wextra -Werror \
    tests/exec-memory/host-vm-probe.c \
    -Wl,-x86_64_layout_emulation -Wl,-pagezero_size,0x100000000 \
    -o "$build_dir/host-vm-probe"
codesign --force --sign - --entitlements tests/platform/entitlements.plist "$build_dir/host-vm-probe"
codesign --verify --strict "$build_dir/host-vm-probe"
shasum -a 256 tests/exec-memory/host-vm-probe.c
"$build_dir/host-vm-probe"
