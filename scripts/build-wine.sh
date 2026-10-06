#!/usr/bin/env bash
# Native ARM64 M0 build, isolated from Madeira's iOS runtime changes.
# Usage: scripts/build-wine.sh [all|prepare|configure|make]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${AOE2_WORK_ROOT:-$HOME/aoe2-poc-work}"
# Profiles keep candidate source/build trees separate from the M0 baseline.
PROFILE="${AOE2_WINE_PROFILE:-m0}"
case "$PROFILE" in
    m0) PATCH="$ROOT/patches/wine-m0/0001-native-arm64-macos.patch" ;;
    em) PATCH="$ROOT/patches/wine-em/0001-native-arm64-macos-exec-memory.patch" ;;
    *) echo "Unknown AOE2_WINE_PROFILE=$PROFILE (m0 or em)" >&2; exit 2 ;;
esac
# Bootstrapping a new candidate may start from an existing combined patch.
PATCH="${AOE2_WINE_PATCH:-$PATCH}"
SOURCE="$WORK/sources/wine-$PROFILE"
BUILD="$WORK/build/wine-$PROFILE"
BASE=cc893ef9cb17b994bfd1f1a1f7355be55e615623
STEP="${1:-all}"
export SDKROOT="$(xcrun --show-sdk-path)"
export PATH="$WORK/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH"

prepare() {
    if [ ! -e "$SOURCE" ]; then
        mkdir -p "$SOURCE"
        git -C "$SOURCE" init -q
        git -C "$SOURCE" remote add origin https://github.com/willfaust/wine.git
        git -C "$SOURCE" fetch --depth 1 origin "$BASE"
        git -C "$SOURCE" checkout --detach FETCH_HEAD
    fi
    test "$(git -C "$SOURCE" rev-parse HEAD)" = "$BASE" || {
        echo "Wrong base; refusing to change $SOURCE" >&2; exit 1;
    }
    if [ -z "$(git -C "$SOURCE" status --porcelain)" ]; then
        git -C "$SOURCE" apply --check "$PATCH"
        git -C "$SOURCE" apply "$PATCH"
    else
        # Idempotence is permitted only when the complete diff matches ours.
        local actual expected
        actual="$(git -C "$SOURCE" diff --binary --no-ext-diff | shasum -a 256)"
        expected="$(shasum -a 256 < "$PATCH")"
        test "$actual" = "$expected" || {
            echo "$SOURCE contains a different diff; preserve it and inspect manually." >&2; exit 1;
        }
        test -z "$(git -C "$SOURCE" ls-files --others --exclude-standard)" || {
            echo "$SOURCE contains untracked files; refusing to proceed." >&2; exit 1;
        }
        git -C "$SOURCE" apply --reverse --check "$PATCH"
    fi
}
configure() {
    # Reconfiguration does not remove disabled outputs from an older build.
    for driver in ndis winebus winebth wineusb mountmgr nsiproxy; do
        if [ -e "$BUILD/dlls/$driver.sys/aarch64-windows/$driver.sys" ]; then
            echo "Existing driver output in $BUILD; preserve this directory and use a clean build directory." >&2
            exit 1
        fi
    done
    mkdir -p "$BUILD"
    # SDK 27 declares pipe2, but our macOS 26.x runtime does not supply it.
    # Keep the portable pipe+fcntl implementation until the minimum OS changes.
    (cd "$BUILD" && ac_cv_func_pipe2=no "$SOURCE/configure" \
        --enable-archs=aarch64 --without-freetype --disable-tests \
        --disable-ndis.sys --disable-winebus.sys --disable-winebth.sys --disable-wineusb.sys \
        --disable-mountmgr.sys --disable-nsiproxy.sys \
        CC="$(xcrun --find clang)" CXX="$(xcrun --find clang++)" \
        CFLAGS='-O2 -g -mmacosx-version-min=26.5 -Werror=unguarded-availability-new' \
        LDFLAGS='-mmacosx-version-min=26.5' 2>&1 | tee configure.log)
}
build() {
    test -f "$BUILD/Makefile" || { echo "Run configure first." >&2; exit 1; }
    # pipefail ensures signing never hides a failed compile/link.
    (cd "$BUILD" && make -j"${AOE2_JOBS:-6}" 2>&1 | tee make.log)
    AOE2_WINE_PROFILE="$PROFILE" "$ROOT/scripts/sign-runtime.sh"
}
case "$STEP" in
    prepare) prepare ;;
    configure) prepare; configure ;;
    make) prepare; build ;;
    all) prepare; configure; build ;;
    *) echo "Usage: $0 [all|prepare|configure|make]" >&2; exit 2 ;;
esac
