#!/bin/sh
# Build and exercise the macOS facilities needed by the local Wine/FEX POC.
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo 'ERROR: run natively on Apple Silicon macOS 26.5 or newer.' >&2
    exit 1
fi
version=$(sw_vers -productVersion)
major=${version%%.*}
minor=${version#*.}
minor=${minor%%.*}
if [ "$major" -lt 26 ] || { [ "$major" -eq 26 ] && [ "$minor" -lt 5 ]; }; then
    echo 'ERROR: macOS 26.5 or newer is required.' >&2
    exit 1
fi
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/aoe2-platform.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
printf 'Host: macOS %s (%s)\nSDK: %s\n' "$version" "$(sw_vers -buildVersion)" "$(xcrun --show-sdk-version)"
csrutil status
printf 'Boot arguments: '
sysctl -n kern.bootargs
xcrun clang -arch arm64 -mmacosx-version-min=26.5 -Wall -Wextra -Werror \
    tests/platform/capabilities.c tests/platform/x18.S -pthread \
    -Wl,-x86_64_layout_emulation -Wl,-pagezero_size,0x100000000 \
    -o "$build_dir/capabilities"
codesign --force --sign - --entitlements tests/platform/entitlements.plist "$build_dir/capabilities"
codesign --verify --strict "$build_dir/capabilities"
"$build_dir/capabilities"
