#!/usr/bin/env bash
# P1.4 — locked source acquisition (plan §7 P1.4 / §16 / §17).
#
# Reproducibly fetches the four pinned sources (blobless partial clones) and the
# LLVM/MinGW PE toolchain into the out-of-repo work root, then VERIFIES every
# acquisition against the SHA pins recorded in sources.lock.json. It is
# idempotent: a component that already exists at the correct commit is skipped;
# a mismatch aborts (never silently rewrites your working tree).
#
#   clone:  git clone --filter=blob:none --no-checkout <url> <path>
#           then `git checkout <commit>` (blobs fetched on demand).
#   tool:   curl -L --fail <url> <tarball>; shasum -a 256 must match the pin.
#
# Submodule working trees are NOT initialized here (P1.2 scope); their gitlink
# SHAs are recorded in sources.lock.json for later use.
set -uo pipefail

WORK="${AOE2_WORK_ROOT:-/Users/szotyesz/aoe2-poc-work}"
SRV="$WORK/sources"
TL="$WORK/toolchains"
mkdir -p "$SRV" "$TL"

# --- locked pins (must match sources.lock.json) ---
MADEIRA_URL="https://github.com/willfaust/Madeira.git";  MADEIRA_SHA="bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120"
WINE_URL="https://github.com/willfaust/wine.git";        WINE_SHA="3a54f56896c85c932870afe6fd91404bbbcb74c8"
FEX_URL="https://github.com/willfaust/FEX.git";          FEX_SHA="be778d7ba5b98bee0405fd1d6a50d305a0807df0"
DXMT_URL="https://github.com/willfaust/dxmt.git";        DXMT_SHA="8937c08c38f5cb867d995f99b2323739a9f6ffdf"

LLVM_TARBALL="llvm-mingw-20260421-ucrt-macos-universal.tar.xz"
LLVM_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/20260421/$LLVM_TARBALL"
LLVM_SHA256="bd85a3975723815cef28dbbd2ca2cb0c926f6b348a12a0453f39f7af273cb3f7"
LLVM_DIR="llvm-mingw-20260421-ucrt-macos-universal"

pass=0; fail=0
ok(){ echo "  OK: $*"; pass=$((pass+1)); }
bad(){ echo "  FAIL: $*"; fail=$((fail+1)); }

echo "== P1.4 locked source acquisition =="
echo "work root: $WORK"
echo

# fetch_git <name> <url> <sha>   (local dir = $SRV/<name>)
fetch_git(){
  local name="$1" url="$2" sha="$3" d="$SRV/$1"
  echo "-- $name"
  if [ -d "$d/.git" ]; then
    local cur; cur="$(git -C "$d" rev-parse HEAD 2>/dev/null)"
    if [ "$cur" = "$sha" ]; then ok "present at pinned $sha (skip)"; return 0; fi
    # present but wrong commit: try a safe checkout if the tree is clean, else abort
    if [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]; then
      bad "present at $cur but locked is $sha, and tree is dirty — not modifying"; return 1
    fi
    echo "  re-checking out pinned $sha ..."
    if git -C "$d" fetch --quiet origin "$sha" 2>/dev/null && git -C "$d" checkout --quiet "$sha"; then
      ok "re-checked out to $sha"
    else bad "could not checkout $sha"; return 1
    fi
  else
    rm -rf "$d"
    echo "  cloning (blobless, no submodule init) ..."
    if git clone --filter=blob:none --no-checkout --quiet "$url" "$d" 2>/dev/null \
       && git -C "$d" checkout --quiet "$sha"; then
      ok "cloned at $sha"
    else bad "clone/checkout failed"; return 1
    fi
  fi
  # verify
  [ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" = "$sha" ] && ok "HEAD == lock" || bad "HEAD mismatch"
}

fetch_git madeira "$MADEIRA_URL" "$MADEIRA_SHA" || true
fetch_git wine-fork "$WINE_URL" "$WINE_SHA" || true
fetch_git fex-fork "$FEX_URL" "$FEX_SHA" || true
fetch_git dxmt-fork "$DXMT_URL" "$DXMT_SHA" || true
echo

# --- LLVM/MinGW toolchain ---
echo "-- llvm-mingw ($LLVM_TARBALL)"
tarball="$TL/$LLVM_TARBALL"
if [ -f "$tarball" ]; then
  actual="$(shasum -a 256 "$tarball" | awk '{print $1}')"
  if [ "$actual" = "$LLVM_SHA256" ]; then ok "tarball present, SHA-256 verified"; else bad "tarball SHA mismatch: $actual"; fi
else
  echo "  downloading ..."
  if curl -fL --fail --retry 3 -o "$tarball.part" "$LLVM_URL" 2>/dev/null; then
    actual="$(shasum -a 256 "$tarball.part" | awk '{print $1}')"
    if [ "$actual" = "$LLVM_SHA256" ]; then mv "$tarball.part" "$tarball"; ok "downloaded, SHA-256 verified"; else rm -f "$tarball.part"; bad "downloaded tarball SHA mismatch: $actual"; fi
  else rm -f "$tarball.part"; bad "download failed"; fi
fi
if [ -f "$tarball" ] && [ ! -d "$TL/$LLVM_DIR" ]; then
  echo "  extracting ..."
  tar -xf "$tarball" -C "$TL" && ok "extracted $TL/$LLVM_DIR" || bad "extract failed"
fi
if [ -d "$TL/$LLVM_DIR/bin" ] && [ -x "$TL/$LLVM_DIR/bin/arm64ec-w64-mingw32-gcc" ]; then
  ok "arm64ec PE cross-compiler present"
else
  bad "arm64ec-w64-mingw32-gcc missing after extraction"
fi
echo

echo "== summary: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
