#!/usr/bin/env bash
# P1.4 — first concrete build steps: the DXMT fork (D3D11 -> Metal).
#
# DXMT is a MESON project (meson.build + meson.options). It ships cross/
# native presets under its source root:
#   build-osx.txt            native macOS host (clang/clang++) — STUBBED M0-M2
#   build-arm64ec-win.txt    ARM64EC PE (winemetal/d3d11); its [binaries] point
#                            at our pinned toolchain
#                            toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin/arm64ec-w64-mingw32-clang
# The preset uses meson's `@GLOBAL_SOURCE_ROOT@` token for the toolchain path,
# so the build root must be arranged such that <root>/toolchains/... resolves
# to the llvm-mingw dir (a symlink suffices). Submodules external/nvapi and
# include/native/directx (sources.lock.json) must be populated first.
#
# M0 GATE: recorded recipe, do not run yet. Native Metal path is M3 (M0-M2
# stubbed per plan §2.5/§7).
set -uo pipefail

export PATH="/opt/homebrew/bin:$PATH"
WORK="${AOE2_WORK_ROOT:-/Users/szotyesz/aoe2-poc-work}"
DX="$WORK/sources/dxmt-fork"
BUILD="$WORK/build/dxmt"
PE="$WORK/toolchains/llvm-mingw-20260421-ucrt-macos-universal"
STEP="${1:-native}"

[ -d "$DX/.git" ] || { echo "FATAL: dxmt-fork not found at $DX (run scripts/fetch-sources.sh)"; exit 2; }

echo "[submodules] initializing external/nvapi + include/native/directx (blobless => on demand)"
git -C "$DX" submodule update --init --recursive

# The arm64ec preset references <root>/toolchains/llvm-mingw-... ; arrange that.
if [ "$STEP" = "arm64ec" ]; then
  echo "[toolchain] exposing $PE at $DX/toolchains/llvm-mingw-20260421-ucrt-macos-universal"
  mkdir -p "$DX/toolchains"
  ln -sfn "$PE" "$DX/toolchains/llvm-mingw-20260421-ucrt-macos-universal"
fi

case "$STEP" in
  native)
    echo "[meson] native macOS (build-osx.txt) — M3 path, stubbed M0-M2"
    meson setup "$BUILD/native" "$DX" --native-file "$DX/build-osx.txt"
    ninja -C "$BUILD/native"
    ;;
  arm64ec)
    echo "[meson] ARM64EC PE (build-arm64ec-win.txt)"
    meson setup "$BUILD/arm64ec" "$DX" --cross-file "$DX/build-arm64ec-win.txt"
    ninja -C "$BUILD/arm64ec"
    ;;
  *) echo "usage: $0 [native|arm64ec]"; exit 2 ;;
esac
echo "[done]"
