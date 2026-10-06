#!/usr/bin/env bash
# P1.4 — first concrete ARM64 build steps: the selected Wine (willfaust fork).
#
# Records the WORKING Darwin-host build recipe (verified by a successful
# `./configure` on this M4 host, plan §7 P1 exit "selected Wine host
# configuration succeeds"). The result is a native aarch64 Darwin host (Wine
# server/ntdll-host objects) plus ARM64EC + i386 PE guest modules (ntdll PE,
# kernel32 PE, ...). Do NOT run this to completion until M0 is authorized:
# `make` is a long build; this script exists to make the first build steps
# concrete and reproducible.
#
# Usage:
#   scripts/build-wine.sh            # configure + build (make -j)
#   scripts/build-wine.sh configure  # configure only
#   scripts/build-wine.sh make       # build only (after configure)
#
# Prereqs (see docs/toolchains.md): llvm-mingw PE toolchain at $AOE2_WORK_ROOT
# (from P1.4 fetch), Homebrew cmake/ninja/meson/pkgconf + keg-only bison, and
# the pinned madeira + wine-fork sources at $AOE2_WORK_ROOT/sources.
set -uo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:$PATH"
WORK="${AOE2_WORK_ROOT:-/Users/szotyesz/aoe2-poc-work}"
WINE="$WORK/sources/wine-fork"
MADEIRA="$WORK/sources/madeira"
BUILD="$WORK/build/wine"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
STEP="${1:-all}"

[ -d "$WINE" ]   || { echo "FATAL: wine-fork not found at $WINE (run scripts/fetch-sources.sh)"; exit 2; }
[ -d "$MADEIRA" ] || { echo "FATAL: madeira not found at $MADEIRA (run scripts/fetch-sources.sh)"; exit 2; }

# ---- ADAPT (M0 build input): the wine fork hard-includes
#      build/madeira_cfg.h from ntdll (sync.c / system.c). The wine tree's
#      .gitignore excludes /build/, so copy the pinned Madeira build input in.
echo "[adapt] placing build input sources/wine-fork/build/madeira_cfg.h"
mkdir -p "$WINE/build"
cp -f "$MADEIRA/build/madeira_cfg.h" "$WINE/build/madeira_cfg.h"
echo "  -> $(wc -l < "$WINE/build/madeira_cfg.h") lines from $MADEIRA"

configure(){
  echo "[configure] Wine (willfaust) on $(uname -m) Darwin host"
  mkdir -p "$BUILD"
  ( cd "$BUILD" && "$WINE/configure" \
      --enable-archs=arm64ec \
      --without-freetype \
      2>&1 | tee "$BUILD/config.configure.out" )
  local rc=${PIPESTATUS[0]}
  echo "  configure exit: $rc"
  [ "$rc" -eq 0 ] && [ -f "$BUILD/Makefile" ]
}

build(){
  [ -f "$BUILD/Makefile" ] || { echo "FATAL: no Makefile (run configure first)"; exit 1; }
  echo "[make] -j$JOBS (long; this is the M0 entry point — abort with Ctrl-C if not ready)"
  ( cd "$BUILD" && make -j"$JOBS" 2>&1 | tee "$BUILD/make.out" )
}

case "$STEP" in
  configure) configure || { echo "configure FAILED"; exit 1; } ;;
  make)      build      || { echo "make FAILED"; exit 1; } ;;
  all)       configure && build ;;
  *) echo "usage: $0 [configure|make|all]"; exit 2 ;;
esac
echo "[done] $STEP"
