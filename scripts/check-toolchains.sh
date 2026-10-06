#!/usr/bin/env bash
# P1.3 — host and PE compiler discovery/inspection (plan §7, P1.3).
#
# Compiles five minimal probes into SEPARATE directories and inspects each PE
# artifact with llvm-readobj (file header / machine, import table, export
# table, load config). Only TC-HOST is executed (natively on the ARM64 Darwin
# host). TC-A64/EC/X64/X86 are compile+inspect only; they are NOT executed
# (plan: "compilation does not imply execution yet").
#
# Note on ARM64EC detection: the loader marker for an ARM64EC image is the PE
# Machine field IMAGE_FILE_MACHINE_ARM64EC (0xA641). The mstorsjo UCRT build
# does NOT emit an `__ISARM64EC` import (that is a CRT runtime flag, not the
# loader marker), so we assert on the 0xA641 machine type, which is how the
# Windows loader distinguishes EC from plain ARM64 (0xAA64). `file(1)`
# mislabels 0xA641 as "x86-64"; llvm-readobj is authoritative.
#
# Evidence layout: $AOE2_WORK_ROOT/probes/tc-<id>/  (source, build log,
# artifact, readobj dump). Machine-readable summary printed at the end.
set -uo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:$PATH"
WORK="${AOE2_WORK_ROOT:-/Users/szotyesz/aoe2-poc-work}"
PE="$WORK/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
HOST_CC="$(xcrun -f clang)"
SDK="$(xcrun --show-sdk-path)"
READOBJ="$PE/llvm-readobj"
OUT="$WORK/probes"
rm -rf "$OUT"; mkdir -p "$OUT"

pass=0; fail=0
ok(){ echo "  PASS: $*"; pass=$((pass+1)); }
bad(){ echo "  FAIL: $*"; fail=$((fail+1)); }
# machine type string, e.g. IMAGE_FILE_MACHINE_ARM64EC
machine_of(){ "$READOBJ" --file-header "$1" 2>/dev/null | grep -oE "IMAGE_FILE_MACHINE_[A-Z0-9]+" | head -1; }
has_imports(){ "$READOBJ" --coff-imports "$1" 2>/dev/null | grep -q "Import {"; }

echo "== P1.3 toolchain probe =="
echo "host     : $(sw_vers -productVersion 2>/dev/null) / $(uname -m)"
echo "host cc  : $HOST_CC ($("$HOST_CC" --version 2>&1 | head -1))"
echo "sdk      : $SDK ($(xcrun --show-sdk-version))"
echo "bison    : $(bison --version 2>&1 | head -1) @ $(command -v bison)"
echo "cmake    : $(cmake --version 2>&1 | head -1)   ninja: $(ninja --version 2>&1)   meson: $(meson --version 2>&1)"
echo "PE bin   : $PE"
echo "PE clang : ($("$PE/x86_64-w64-mingw32-gcc" --version 2>&1 | head -1))"
echo "out      : $OUT"
echo

# ---- TC-HOST : ARM64 Darwin, executed natively ----
d="$OUT/tc-host"; mkdir -p "$d"
printf '#include <stdio.h>\nint main(void){ printf("TC-HOST arm64\\n"); return 0; }\n' > "$d/tc_host.c"
if "$HOST_CC" -isysroot "$SDK" -o "$d/tc_host" "$d/tc_host.c" 2>"$d/build.log"; then
  file "$d/tc_host" | sed 's/^/  /'
  case "$(file "$d/tc_host")" in *arm64*) ok "Mach-O arm64";; *) bad "not arm64";; esac
  out=$("$d/tc_host"); rc=$?
  echo "  run: $out (rc=$rc)"
  [ "$rc" -eq 0 ] && ok "executes natively, exit 0" || bad "run rc=$rc"
else bad "compile"; sed 's/^/  /' "$d/build.log"; fi
echo

# ---- TC-A64 : Windows ARM64 (aarch64) ----
d="$OUT/tc-a64"; mkdir -p "$d"
printf '#include <windows.h>\nint main(void){ DWORD id = GetCurrentProcessId(); (void)id; return 42; }\n' > "$d/tc_a64.c"
if "$PE/aarch64-w64-mingw32-gcc" -o "$d/tc_a64.exe" "$d/tc_a64.c" 2>"$d/build.log"; then
  file "$d/tc_a64.exe" | sed 's/^/  /'
  "$READOBJ" --file-header "$d/tc_a64.exe" 2>&1 | grep -E "Machine|Characteristics" | sed 's/^/  /'
  "$READOBJ" --coff-imports "$d/tc_a64.exe" 2>&1 | grep -E "^  Name: " | sed 's/^/  /' | sort -u | head
  "$READOBJ" --file-header --coff-imports --coff-load-config "$d/tc_a64.exe" > "$d/inspect.txt" 2>&1
  [ "$(machine_of "$d/tc_a64.exe")" = "IMAGE_FILE_MACHINE_ARM64" ] && ok "PE machine ARM64 (0xAA64)" || bad "machine not ARM64"
  has_imports "$d/tc_a64.exe" && ok "has PE import table (CRT + KERNEL32 thunks)" || bad "no import table"
else bad "compile"; sed 's/^/  /' "$d/build.log"; fi
echo

# ---- TC-EC : Windows ARM64EC (minimal EXE + exported-function DLL) ----
d="$OUT/tc-ec"; mkdir -p "$d"
printf '#include <windows.h>\nint main(void){ return 7; }\n' > "$d/tc_ec.c"
printf 'int EcProbeAdd(int a, int b){ return a + b; }\n' > "$d/tc_ec_lib.c"
printf 'LIBRARY tc_ec_lib\nEXPORTS\n    EcProbeAdd\n' > "$d/tc_ec_lib.def"
if "$PE/arm64ec-w64-mingw32-gcc" -o "$d/tc_ec.exe" "$d/tc_ec.c" 2>"$d/exe.build.log" \
 && "$PE/arm64ec-w64-mingw32-gcc" -shared -o "$d/tc_ec_lib.dll" "$d/tc_ec_lib.c" "$d/tc_ec_lib.def" 2>"$d/dll.build.log"; then
  echo "  [file(1) NOTE: labels 0xA641 as 'x86-64'; readobj below is authoritative]"
  file "$d/tc_ec.exe" "$d/tc_ec_lib.dll" | sed 's/^/  /'
  echo "  [EXE machine]"; "$READOBJ" --file-header "$d/tc_ec.exe" 2>&1 | grep -E "Machine|Characteristics" | sed 's/^/    /'
  echo "  [EXE DLL imports]"; "$READOBJ" --coff-imports "$d/tc_ec.exe" 2>&1 | grep -E "^  Name: " | sed 's/^/    /' | sort -u
  echo "  [DLL exports]"; "$READOBJ" --coff-exports "$d/tc_ec_lib.dll" 2>&1 | grep -E "Name: |Ordinal" | sed 's/^/    /'
  "$READOBJ" --file-header --coff-imports --coff-load-config "$d/tc_ec.exe" > "$d/inspect.txt" 2>&1
  "$READOBJ" --file-header --coff-exports "$d/tc_ec_lib.dll" >> "$d/inspect.txt" 2>&1
  [ "$(machine_of "$d/tc_ec.exe")" = "IMAGE_FILE_MACHINE_ARM64EC" ] && ok "EXE machine ARM64EC (0xA641) — the EC loader marker" || bad "EXE machine not ARM64EC"
  [ "$(machine_of "$d/tc_ec_lib.dll")" = "IMAGE_FILE_MACHINE_ARM64EC" ] && ok "DLL machine ARM64EC (0xA641)" || bad "DLL machine not ARM64EC"
  has_imports "$d/tc_ec.exe" && ok "EXE has PE import table" || bad "EXE no import table"
  "$READOBJ" --coff-exports "$d/tc_ec_lib.dll" 2>&1 | grep -q "EcProbeAdd" && ok "DLL exports EcProbeAdd" || bad "DLL missing EcProbeAdd export"
  # __ISARM64EC: expected ABSENT in mstorsjo build; record the observation, do not fail.
  if "$READOBJ" --coff-imports "$d/tc_ec.exe" 2>&1 | grep -q "__ISARM64EC"; then
    echo "  NOTE: EXE imports __ISARM64EC (present)"
  else
    echo "  NOTE: EXE does not import __ISARM64EC (mstorsjo marks EC via machine 0xA641 only)"
  fi
else bad "compile exe/dll"; sed 's/^/  /' "$d/exe.build.log" "$d/dll.build.log" 2>/dev/null; fi
echo

# ---- TC-X64 : Windows x86-64 ----
d="$OUT/tc-x64"; mkdir -p "$d"
printf '#include <windows.h>\nint main(void){ DWORD id = GetCurrentProcessId(); (void)id; return 42; }\n' > "$d/tc_x64.c"
if "$PE/x86_64-w64-mingw32-gcc" -o "$d/tc_x64.exe" "$d/tc_x64.c" 2>"$d/build.log"; then
  file "$d/tc_x64.exe" | sed 's/^/  /'
  "$READOBJ" --file-header "$d/tc_x64.exe" 2>&1 | grep -E "Machine|Characteristics" | sed 's/^/  /'
  "$READOBJ" --file-header --coff-imports "$d/tc_x64.exe" > "$d/inspect.txt" 2>&1
  [ "$(machine_of "$d/tc_x64.exe")" = "IMAGE_FILE_MACHINE_AMD64" ] && ok "PE machine AMD64 (0x8664)" || bad "machine not AMD64"
else bad "compile"; sed 's/^/  /' "$d/build.log"; fi
echo

# ---- TC-X86 : Windows i386 (required before M2) ----
d="$OUT/tc-x86"; mkdir -p "$d"
printf '#include <windows.h>\nint main(void){ DWORD id = GetCurrentProcessId(); (void)id; return 42; }\n' > "$d/tc_x86.c"
if "$PE/i686-w64-mingw32-gcc" -o "$d/tc_x86.exe" "$d/tc_x86.c" 2>"$d/build.log"; then
  file "$d/tc_x86.exe" | sed 's/^/  /'
  "$READOBJ" --file-header "$d/tc_x86.exe" 2>&1 | grep -E "Machine|Characteristics" | sed 's/^/  /'
  "$READOBJ" --file-header --coff-imports "$d/tc_x86.exe" > "$d/inspect.txt" 2>&1
  [ "$(machine_of "$d/tc_x86.exe")" = "IMAGE_FILE_MACHINE_I386" ] && ok "PE machine I386 (0x14C)" || bad "machine not I386"
else bad "compile"; sed 's/^/  /' "$d/build.log"; fi
echo

echo "== summary: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
