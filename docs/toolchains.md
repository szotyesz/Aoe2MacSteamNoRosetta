# P1.1 — Host toolchain and build-tool inventory

Date: 2026-10-05. Recorded on the local POC host. The native Darwin inventory and installed Windows PE compiler are recorded below.

## P0-BASE re-run (required before toolchain work)

Command: `./scripts/test-platform.sh` from the repository root (baseline `bfac0ac`).

```text
Host: macOS 26.6.2 (25G83)
SDK: 27.0
System Integrity Protection status: disabled.
Boot arguments: amfi_get_out_of_my_way=0x1
page size: sysconf=4096 Mach=4096
low mapping=0x7ffe0000 individual 4 KiB protection=1 data=1
PASS memory (exit=0 signal=0)
x18: enabled=1 value=0x1234 restored=1
PASS x18 (exit=0 signal=0)
TSO fresh thread: enable=0 disable=0
TSO main thread: enable=0 disable=0
PASS tso (exit=0 signal=0)
Exit Code: 0
```

All three isolated children PASS, overall exit 0. Baseline preserved.

## Host

| Item | Value | Evidence command |
|---|---|---|
| OS | macOS 26.6.2 (25G83) | `sw_vers` |
| Kernel | Darwin 25.6.0, `RELEASE_ARM64_T8132` | `uname -a` |
| Arch | arm64 | `arch` |
| Chip / model | Apple M4, `Mac16,13` | `sysctl hw.model`, `machdep.cpu.brand_string` |
| Active developer dir | `/Library/Developer/CommandLineTools` (Command Line Tools) | `xcode-select -p` |
| Full Xcode | Present at `/Applications/Xcode.app` but **not** the active developer dir | `ls -d /Applications/Xcode.app/Contents/Developer` |
| SDK path | `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` | `xcrun --show-sdk-path` |
| SDK version | 27.0 | `xcrun --show-sdk-version` |
| Metal framework | Present in active (CLT) SDK | `ls .../MacOSX.sdk/.../Metal.framework` |

## Compiler and linker (native Darwin)

| Item | Value | Evidence command |
|---|---|---|
| C compiler | Apple clang 21.0.0 (`clang-2100.3.34.2`), target `arm64-apple-darwin25.6.0` | `xcrun clang --version` |
| Compiler path | `/Library/Developer/CommandLineTools/usr/bin/clang` | `xcrun -f clang` |
| Linker | Apple `ld`, `PROJECT:ld-27037.1`, LTO LLVM 21.0.0, TAPI 21.0.0; supports `arm64e`, `x86_64`, ... | `xcrun -f ld`, `xcrun ld -v` |
| Linker path | `/Library/Developer/CommandLineTools/usr/bin/ld` | `xcrun -f ld` |

`/usr/bin/clang`, `clang++`, `cc`, `ar`, `ld`, `make`, `git`, `python3`, `perl`, `flex`,
`bison` are all present and universal Mach-O (`x86_64 arm64e`); they execute their arm64e
slice natively (no Rosetta). `/usr/bin/clang`/`cc`/`ld` are shims that dispatch to the active
developer dir (CLT), so the effective native compiler is Apple clang 21.

## Build tools

| Tool | Path | Status / arch |
|---|---|---|
| `clang` / `cc` | `/usr/bin/clang`, `/usr/bin/cc` | present, `x86_64 arm64e` |
| `clang++` | `/usr/bin/clang++` | present, `x86_64 arm64e` |
| `ar` | `/usr/bin/ar` | present, `x86_64 arm64e` |
| `ld` | `/usr/bin/ld` | present, `x86_64 arm64e` |
| `make` | `/usr/bin/make` | present, `x86_64 arm64e` |
| `git` | `/usr/bin/git` | present, `x86_64 arm64e`, version 2.54.0 (Apple Git-157) |
| `python3` | `/usr/bin/python3` | present, `x86_64 arm64e` |
| `perl` | `/usr/bin/perl` | present (needed by Wine `configure`) |
| `flex` | `/usr/bin/flex` | present (needed by Wine `configure`) |
| `bison` | `/usr/bin/bison` | present (needed by Wine `configure`) |
| `file` / `lipo` | `/usr/bin/file`, `/usr/bin/lipo` | present |
| `curl` | `/usr/bin/curl` | present (source acquisition) |
| `shasum` | `/usr/bin/shasum` | present (SHA-256 via `shasum -a 256`) |
| `xxd` | `/usr/bin/xxd` | present |

Shell interpreters: `SHELL=/bin/zsh`; `/bin/bash` and `/bin/zsh` are both present, universal
`x86_64 arm64e`. Script-driven build steps run natively.

## Host build tools (installed P1.3, 2026-10-06, via Homebrew)

Previously missing; installed with `brew install cmake ninja meson pkgconf bison` (all
`bottle` installs, no compilation). Native arm64 binaries at `/opt/homebrew/bin`.

| Tool | Version | Where it becomes required |
|---|---|---|
| `cmake` | 4.4.4 | FEX (CMake) + DXMT (meson uses ninja) |
| `ninja` | 1.13.2 | CMake `Ninja` generator (FEX), meson backend (DXMT) |
| `meson` | 1.12.1 | DXMT build system |
| `pkgconf` | 3.0.7 | native dependency resolution |
| `bison` | 3.8.2 (keg-only) | Wine `tools/wrc` parser. **Must** be on PATH ahead of the system bison: `/opt/homebrew/opt/bison/bin`. |

> **bison note:** the system `/usr/bin/bison` is 2.3 (too old for the Wine `wrc` grammar).
> Homebrew bison 3.8.2 is keg-only. Scripts therefore export
> `PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:$PATH"` before running Wine `configure`.

Do not assume a full Xcode install is required to use CLT; full Xcode is present and can be
selected later only if a component's Metal/shader-conversion build needs it (see M3.1, which
also requires separate LLVM 15 libraries for DXMT shader conversion).

## Notes

- The P0 platform probe links with `-Wl,-x86_64_layout_emulation -Wl,-pagezero_size,0x100000000`
  under this exact CLT toolchain; that combination is the verified P0 baseline.
- The native inventory above is P1.1. The Windows-PE (LLVM/MinGW) family and the
  TC-HOST/A64/EC/X64/X86 probes are recorded in the P1.3 section below (2026-10-06).

## P1.3 — Windows-PE (LLVM/MinGW) toolchain + build checks (2026-10-06)

### Toolchain: llvm-mingw-20260421-ucrt-macos-universal

Acquired per P1.4 (SHA-256 `bd85a3975723815cef28dbbd2ca2cb0c926f6b348a12a0453f39f7af273cb3f7`
verified locally) into `$AOE2_WORK_ROOT/toolchains/`. Universal (x86_64+arm64) host build;
all four PE targets + LLVM binutils confirmed present and **executing natively on the ARM64
host** (no Rosetta):

| Driver | PE target | Machine emitted | Verified |
|---|---|---|---|
| `arm64ec-w64-mingw32-gcc` (clang 22.1.4) | Windows ARM64EC | `IMAGE_FILE_MACHINE_ARM64EC` (0xA641) | EXE + `-shared` DLL |
| `aarch64-w64-mingw32-gcc` | Windows ARM64 | `IMAGE_FILE_MACHINE_ARM64` (0xAA64) | EXE |
| `x86_64-w64-mingw32-gcc` | Windows x86-64 | `IMAGE_FILE_MACHINE_AMD64` (0x8664) | EXE |
| `i686-w64-mingw32-gcc` | Windows i386 | `IMAGE_FILE_MACHINE_I386` (0x14C) | EXE |

`llvm-readobj` (same toolchain) is authoritative for machine/import/export/load-config.

> **ARM64EC detection:** the Windows loader marker for an EC image is the PE Machine field
> `IMAGE_FILE_MACHINE_ARM64EC` (0xA641) — that is how the loader distinguishes EC from plain
> ARM64 (0xAA64). The mstorsjo UCRT build does **not** emit an `__ISARM64EC` import (that is a
> CRT runtime flag, not the loader marker), so the probe asserts on 0xA641. `file(1)`
> mislabels 0xA641 as "x86-64"; `llvm-readobj --file-header` is authoritative.

### TC-HOST/A64/EC/X64/X86 probes — `scripts/check-toolchains.sh` (10/10 PASS)

Evidence under `$AOE2_WORK_ROOT/probes/tc-<id>/` (source, build log, artifact, `inspect.txt`).
TC-HOST is the only probe executed (natively). TC-A64/EC/X64/X86 are compile+inspect only
("compilation does not imply execution yet" — plan §7).

| Probe | Result | Evidence |
|---|---|---|
| TC-HOST | Mach-O arm64; runs natively, prints banner, exit 0 | `arm64-apple-darwin26` |
| TC-A64 | PE machine ARM64 (0xAA64); import table present | `GetCurrentProcessId` is an ARM64 syscall thunk (no import) |
| TC-EC | EXE + DLL machine ARM64EC (0xA641); EXE import table present; DLL exports `EcProbeAdd` | `__ISARM64EC` import absent (expected) |
| TC-X64 | PE machine AMD64 (0x8664) | — |
| TC-X86 | PE machine I386 (0x14C) | satisfies plan's "i386 compiler check before M2" |

### M0 build configuration (2026-10-06)

M0 builds Wine 11.4 at the exact upstream base recorded in `sources.lock.json`, plus
`patches/wine-m0/0001-native-arm64-macos.patch`. Both host executables are thin ARM64
Mach-O; Windows modules and probes use plain ARM64 (0xAA64), not ARM64EC.

`scripts/build-wine.sh` sets `SDKROOT` explicitly when invoking the compiler by its
absolute `xcrun` path. It uses the installed LLVM/MinGW compiler for PE outputs,
Homebrew bison 3.8.2, deployment target 26.5, `ac_cv_func_pipe2=no`, and
`-Werror=unguarded-availability-new`. SDK 27 provides a weak `pipe2` import that is
absent on this macOS 26.x runtime; the portable fallback is necessary.

The console-only profile disables NDIS, winebus, winebth, wineusb, mountmgr and nsiproxy drivers. They
request executable heaps; RWX commit fails on this host and their unchecked null
heap causes startup crashes. These drivers and executable heaps need a separate
implementation/test gate before later device-dependent workloads. No failure is
reported as a successful allocation. Other optional dependencies (FreeType,
FFmpeg, Vulkan, audio) are outside this console acceptance stage.

The earlier Madeira ARM64EC configuration succeeded, but `make` failed on iOS-only
win32u hooks. It remains a source reference for M1, not M0 build evidence. See
[source selection](source-selection.md) and [M0 results](m0-results.md).
