#!/usr/bin/env bash
# P1.4 — first concrete build steps: the FEX fork (ARM64EC JIT).
#
# The EC guest JIT is the CMake target `arm64ecfex` (SHARED) defined in
#   sources/fex-fork/Source/Windows/ARM64EC/CMakeLists.txt
# (patched for Wine via `patch_library_wine(arm64ecfex)`; the POC loads it as
# xtajit64.dll). FEX is a CMake project; its External/* submodules (16 pinned
# gitlinks, see sources.lock.json) MUST be populated before configuring, and
# because the clone is blobless they are fetched on demand.
#
# M0 GATE: this script is the recorded recipe, not something to run yet. A full
# FEX configure+build is an M0 activity (see plan §7) and needs the host +
# cross toolchains on PATH and the submodules checked out.
set -uo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:$PATH"
WORK="${AOE2_WORK_ROOT:-/Users/szotyesz/aoe2-poc-work}"
FEX="$WORK/sources/fex-fork"
BUILD="$WORK/build/fex"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

[ -d "$FEX/.git" ] || { echo "FATAL: fex-fork not found at $FEX (run scripts/fetch-sources.sh)"; exit 2; }

echo "[submodules] initializing 16 pinned External/* + cpp-optparse (blobless => fetched on demand)"
git -C "$FEX" submodule update --init --recursive

echo "[configure] FEX (CMake + Ninja) — target arm64ecfex"
cmake -S "$FEX" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  2>&1 | tee "$BUILD/configure.log"

echo "[build] arm64ecfex (-j$JOBS)"
cmake --build "$BUILD" --target arm64ecfex -j"$JOBS" 2>&1 | tee "$BUILD/build.log"

echo "[done] look for the EC DLL in $BUILD (target arm64ecfex; POC name xtajit64.dll)"
