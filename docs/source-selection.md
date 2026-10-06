# P1.2 — Source selection and the proposed macOS route

Date: 2026-10-05. **Status: PROPOSAL** (produced for the P1.2 route gate in plan §3.3/§16).
This is not yet a locked recipe — the verified `sources.lock.json` and build recipe are P1.4.
Everything below is *inspected* (source read at the pinned commit); nothing here has been *built*.

## Source acquisition (P1.2 step 1)

Work root (outside the repository, per plan §7): `/Users/szotyesz/aoe2-poc-work/sources/`.
Blobless partial clones (`--filter=blob:none`, no submodule recursion, no build). Each tree was
verified by `git rev-parse HEAD` against the plan §17 pins and the Madeira `.gitmodules` gitlinks.

| Local path | Role | Pinned commit (verified) | Branch | `.gitmodules` gitlink match |
|---|---|---|---|---|
| `madeira/` | App / build orchestration | `8937c08c1719009c147948b94d83d08b9232e365` | `main` | top-level |
| `wine-fork/` | Wine (submodule `wine`) | `3a54f568965d5806e305a390b2c3721b6f65d412` | `madeira-lgpl` | `3a54f56896…` ✓ |
| `fex-fork/` | FEX (submodule `fex`) | `be778d7ba055917a44d190100a24b6b4a92a2366` | `ios-port-2607` | `be778d7ba05…` ✓ |
| `dxmt-fork/` | DXMT (submodule `dxmt`) | `8937c08c1719009c147948b94d83d08b9232e365` | `ios-port` | `8937c08c171…` ✓ |

Recorded submodule URLs (as in `madeira/.gitmodules`): wine → `github.com/willfaust/madeira`
(branch `madeira-lgpl`); fex → `github.com/willfaust/fex-ios-port` (`ios-port-2607`);
dxmt → `github.com/willfaust/dxmt` (`ios-port`). `madeira-dock` → `github.com/willfaust/madeira-dock`
(`main`). Nested FEX submodules (`rpmalloc@5d51f69a`, `SoftFloat@8d3590be`) are gitlinks in
`fex-fork/.gitmodules`; the submodule working dirs are intentionally not populated (P1.2 scope).

## Proposed route (plan §3.3 gate)

**Preferred route (selected):** a verifiable **macOS Wine** source + the **smallest FEX** subset
+ **upstream macOS DXMT**, assembled with **separate Mach tasks** and a **genuine wineserver**.
This is the only route fully consistent with the §1/§3.1 constraints (local POC, ad-hoc signed,
SIP off; do not inherit the single-process iOS model). The **Alternative** (full Madeira
Wine/FEX pair with iOS disabled) is deferred; it is only a fallback if a macOS build proves a
Wine-FEX API mismatch that cannot be bridged locally.

The route is composable from four independent, separately-buildable pieces, each proven to exist
in the pinned sources:

1. **Wine** fork → native Darwin host + ARM64EC (and later i386) **PE** guest farm.
2. **FEX** `arm64ecfex` target → `libarm64ecfex.dll`, staged as **`xtajit64.dll`** (the ARM64EC
   x86/x86-64 JIT). This is the "smallest FEX subset"; the 32-bit `wow64fex` → `xtajit.dll` is
   added only at M2.
3. **DXMT** → native macOS **Metal** bridge (M3), stubbed/null at M0–M2.
4. **LLVM/MinGW** `llvm-mingw-20260421-ucrt-macos-universal` → the arm64ec/i686/x86_64 Windows-PE
   cross-compiler (P1.3 acquisition + probes).

## Source evidence table (one row per component)

| Component | Pinned commit | Upstream base | Feature selected | Proves (file : symbol) | Existing behavior | Host deps | Action |
|---|---|---|---|---|---|---|---|
| Wine fork (`wine-fork`) | `3a54f56` | Wine 11.4 | Native Darwin host + ARM64EC/i386 PE guest + emulator-DLL registration | `loader/wine.inf.in` : `xtajit64.dll`/`xtajit.dll` + `KnownDLLs`; `libs/winecrt0/arm64ec.c` : `__wine_arm64ec_icall_helper`; `configure.ac` : Darwin host cases | autotools; PE farm via `--enable-archs=arm64ec`; Darwin host supported; emulator DLLs exposed through `HKLM\...\Wow64` + KnownDLLs | CLT clang; **bison ≥3** (`tools/wrc`); perl; flex; LLVM/MinGW arm64ec+i686 (PE cross) | **USE** Darwin host + ARM64EC PE; **ADAPT** → drop iOS single-process unix-side, use standard `ntdll` Unix side + separate `wineserver` |
| FEX fork (`fex-fork`) | `be778d7` | FEX-Emu/FEX 3.4.0+ | ARM64EC JIT module + 32-bit WOW64 module | `Source/Windows/ARM64EC/CMakeLists.txt` : `add_library(arm64ecfex …)` + `libarm64ecfex.def`; `Source/Windows/ARM64EC/Module.cpp:953` : `"[build-id] xtajit64 …"`; `CMakeLists.txt:64` : `Darwin`/`iOS` host | CMake; ARM64EC module built "identical to upstream" (no window); guest window is iOS-only (`ENABLE_GUEST_WINDOW`, fatal for ARM64EC); Darwin host accepted | CMake + Ninja; LLVM/MinGW arm64ec+i686 (PE); CLT clang (host) | **USE** `arm64ecfex` (smallest subset, M0–M3); **ADAPT** `wow64fex` to identity mapping at M2; **EXCLUDE** iOS single-process glue |
| DXMT fork (`dxmt-fork`) | `8937c08` | willfaust/dxmt | D3D11→Metal bridge (ARM64EC PE) + native macOS Metal | `build-osx.txt` : `c = 'clang', cpp = 'clang++'`; `build-arm64ec-win.txt` : `arm64ec-w64-mingw32-clang`, `system = 'windows' cpu = 'aarch64'` | Meson; emits `winemetal` + `d3d11`/`dxgi`/`d3d10core`; both a native macOS config and the ARM64EC PE cross config exist | Meson + Ninja; LLVM/MinGW arm64ec (PE); Metal.framework (present); GPTK converter + LLVM 15 (**M3 only**) | **USE** native macOS bridge + ARM64EC PE `winemetal.dll`/`d3d11.dll`; M0–M2 = stub/null device, M3 = enable |
| Madeira app (`madeira`) | `8937c08` | the iOS app | iOS single-process embedding + build orchestration + DLL-farm staging | `docs/WOW64.md` : single Mach task, guest `[B,B+4GB)`; `docs/BUILDING.md` : build order + not-in-repo inputs; `build/fex-arm64ec/build.sh` : `arm64ecfex` → `xtajit64.dll` | Builds the whole stack into one iOS app; pseudo-processes; `madsync`/Fastsync | iOS LLVM, GPTK, `vc_redist.x64`, StikDebug, Apple ID | **USE AS REFERENCE ONLY** (component selection + build order); **EXCLUDE** single-process model, iOS signing, `*_ios.c`, guest window, `madsync`/Fastsync |
| LLVM/MinGW PE toolchain | `20260421` (not fetched) | mstorsjo/llvm-mingw | arm64ec / i686 / x86_64 Windows-PE cross-compiler | `docs/BUILDING.md` : tarball SHA-256 `bd85a3975723815cef28dbbd2ca2cb0c926f6b348a12a0453f39f7af273cb3f7`; `build-arm64ec-win.txt` : `arm64ec-w64-mingw32-clang` | 122 MB third-party toolchain (not in any repo) | It *is* a host dependency: download + SHA-256 verify | **ACQUIRE in P1.3** (TC-EC / TC-X64 / TC-X86 probes) |
| Sync engine (`build/madsync`, `build/rppairing-ios`) | part of `madeira` | Madeira | In-process inter-pseudo-process sync (iOS) | `build/madsync/madsync.c`; `docs/WOW64.md` : Fastsync default since 2026-09-30 | Replaces a separate `wineserver` with in-Mach-task sync | none (source only) | **EXCLUDE** for macOS — use genuine separate `wineserver` IPC (plan M1.5) |

## Incompatible iOS dependencies (explicitly excluded from the macOS route)

These are present in the pinned Madeira/FEX/Wine sources but must NOT be carried into the macOS
POC, per plan §1 (local POC) and §3.1 (do not inherit the single-process model):

- **Single Mach task / pseudo-processes** — `docs/WOW64.md` ("every Windows 'process' is a
  pseudo-process … inside the one Mach task"). macOS POC uses separate Mach tasks and a real
  `wineserver`.
- **Guest window `[B, B+4GB)` / `ENABLE_GUEST_WINDOW`** — the 32-bit host-offset design with
  pointer conversion; iOS-only (FEX CMake makes it fatal for ARM64EC). Start from **identity low
  mappings** (P0-BASE low-mapping probe already PASS at `0x7ffe0000`).
- **`build/ntdll-unix/*_ios.c`, `build/win32u-unix/*_ios.c`** — iOS Unix-side replacements. Use
  Wine's standard `ntdll` Unix side built on the Darwin host instead.
- **`madsync` / Fastsync in-process sync** — EXCLUDE; use separate-`wineserver` IPC.
- **iOS signing / pairing** — StikDebug, Apple ID, `com.apple.developer.*` JIT entitlements.
  macOS POC is local and ad-hoc signed (SIP off, `amfi_get_out_of_my_way=0x1`).
- **`toolchains/llvm-ios-build`** (LLVM built for the `arm64-apple-ios` host) — not needed for the
  macOS host side; the native CLT clang covers it. Only the **PE** cross toolchain
  (`llvm-mingw-20260421-ucrt-macos-universal`) is required.
- **GPTK Metal Shader Converter** — M3 only; not needed for M0–M2.

## Host toolchain gaps (must close before the first build in P1.4/M0)

From `docs/toolchains.md` (P1.1) plus `docs/BUILDING.md`:

| Gap | Status | Needed for |
|---|---|---|
| `cmake` | NOT FOUND | FEX + DXMT configure |
| `ninja` | NOT FOUND | CMake/Meson `Ninja` build |
| `meson` | NOT FOUND | DXMT (winemetal/d3d11 PE) |
| `pkg-config` | NOT FOUND | verify per-component before M3 |
| `bison` ≥ 3.0 | system is **2.3**, no Homebrew bison | Wine `tools/wrc` (PE farm) |
| `llvm-mingw-20260421-ucrt-macos-universal` | not fetched | TC-EC/TC-X64/TC-X86 PE cross-compiles |

None of these blocks recording P1.2. They are P1.3/P1.4/M0 prerequisites and are recorded as
unknowns to resolve then, not fabricated around now.

## Evidence contract (what is verified vs. pending)

- **Inspected (this phase):** all four trees fetched at verified SHAs; Darwin/ARM64EC build paths
  located; the iOS-specific vs. portable boundary identified; host tool gaps recorded.
- **Not yet done (do not claim):** TC-HOST/A64/EC/X64/X86 compiler probes (P1.3); `sources.lock.json`
  + build recipe (P1.4); any build or runtime (M0+).
- **Unknowns left pending:** exact CMake options the FEX ARM64EC configure needs (the first-run
  configure in `build/fex-arm64ec/build.sh` is marked UNVERIFIED upstream); whether the standard
  (non-iOS) Wine `ntdll` Unix side builds cleanly on this Darwin host; the concrete DXMT
  Meson options for the native macOS `winemetal` target. These are resolved in P1.3/P1.4, not here.

## Next (out of scope for P1.2 — do not start without confirmation)

P1.3: acquire the LLVM/MinGW toolchain and run the TC-HOST/A64/EC/X64/X86 compiler probes.
P1.4: pin `sources.lock.json` and write the verified build recipe. Then M0 (A64-HELLO first).
