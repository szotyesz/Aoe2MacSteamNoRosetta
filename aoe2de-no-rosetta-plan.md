# AoE2DE on Apple Silicon without Rosetta — implementation plan for a local POC

Updated: 2026-10-06 (route revision R1). P0 passes; native ARM64 console M0 acceptance passes (32/32 checks) on the Wine 11.4 base. See `docs/m0-results.md` for execution evidence and limitations. The platform baseline commit remains `bfac0ac`.

**Route revision R1 (2026-10-06).** The route review in `docs/route-review.md` confirmed the architecture (native ARM64 Wine, ARM64EC + FEX for x86-64, FEX WoW64 for i386, DXMT for D3D11) and changed the sources and ordering:

- Wine base moves from 11.4 (`cc893ef9cb17`) to the upstream **wine-11.19** tag, commit `455e3509b98a6919fd4ad1def4803e08c41c03b2`, fetched from upstream rather than Madeira's fork. The M0 and EM patches are re-ported by hand (M0.0).
- FEX moves to **upstream FEX main at or after `f18599d09`** (for example `7d3090f78237`), not FEX-2609.1 and not Madeira's fork. DXMT moves to **upstream 3Shain/dxmt main at or after `e94c312`**.
- Madeira becomes a narrow reference only (section 3). MacNeutron, Highball's arm64 line and CrossOver's ARM64 preview are added as comparison references.
- Native simultaneous writable+executable host memory is dropped as a goal. Executable memory follows the consumer split in M0-EM, and EM-2's fail-on-RWX policy does not carry into M1.
- i386/WoW64 becomes its own milestone (M1.6), before Steam.
- A signing-profile milestone (S1) and Wine test-suite lanes are added.

Items marked [unverified] in this plan come from secondary reports and must be checked before relying on them.

## 1. Objective, scope, and known facts

Run the unmodified Windows Steam version of Age of Empires II: Definitive Edition on this Apple Silicon Mac. Use native ARM64 host components, Wine for Windows APIs, FEX for Windows x86/x86-64 instructions, and DXMT for Direct3D 11 rendering through Metal. Finish with practical single-player gameplay and repeated completed multiplayer matches with Windows players.

The working environment is the user's temporary SIP/AMFI-disabled macOS installation. Apple entitlement access was attempted on another installation and did not work. The user is querying Apple independently. Continue local implementation with the ad-hoc signing method that passes P0; do not reintroduce Apple account approval as a prerequisite. A successful POC here says nothing about execution under enabled enforcement.

| Item | Evidence as of this plan | Meaning |
|---|---|---|
| Host | macOS 26.6.2, build 25G83, ARM64 | Actual test environment |
| SDK | 27.0 selected through Command Line Tools | Sufficient for existing platform probe |
| SIP | `csrutil status` reports disabled | Recorded host state |
| AMFI configuration | `kern.bootargs` includes `amfi_get_out_of_my_way=0x1` | Recorded configuration, not an exhaustive audit |
| Platform facilities | `scripts/test-platform.sh` passes | 4 KiB spawning, low mapping, x18 mode, TSO API acceptance |
| Signature | Ad-hoc with unmanaged cross-architecture entitlement | Works locally; no account authorization established |
| Wine runtime | Native ARM64 console M0 build implemented on Wine 11.4 | Console acceptance is tracked in `docs/m0-results.md`; executable heaps/device drivers remain unsupported; re-port to wine-11.19 pending |
| FEX/DXMT | Source references and recipes only; recipes still target Madeira forks | M1–M5 remain pending; recipes must be rewritten for upstream pins |
| macOS 26.5 | Probe deployment target only | Execution on 26.5 has not been verified |
| macOS 27 | Not tested | Both public comparison projects measure on 27; add it to the test matrix when available |
| Rosetta | Apple's macOS 27 release notes say Intel software stops working on macOS 28, except legacy games | Every Rosetta-based Wine stack loses general support after macOS 27; this route does not depend on it |

This POC does not require a launcher UI. A command-line harness, separate Wine server, separate client processes, local prefix, and captured logs are sufficient. Keep the game and Steam files outside tracked source. Do not change the host's security configuration or substitute Rosetta to get a milestone to pass.

## 2. Architecture and non-negotiable boundaries

```text
Native ARM64 macOS launch harness
    -> native ARM64 Wine loader / Unix libraries / wineserver
        -> native Windows ARM64 / ARM64EC Wine modules
        -> FEX emulation backend
            -> x86-64 Windows game/client code
            -> i386 Windows helper code through WoW64, when needed
        -> DXMT Windows frontend + native macOS Metal bridge
            -> Metal / Apple GPU
```

These are different binary formats and build targets. A Windows ARM64EC DLL is a PE file, not a macOS executable. A native macOS loader is Mach-O, not a Windows cross-compile output. ARM64EC is an interoperability ABI; it does not translate x86-64 instructions by itself. FEX must provide the execution backend. WoW64's 32-bit guest side does not imply using a 32-bit macOS host process.

Prefer separate Mach tasks for separate Windows processes. The low-address and 4 KiB capabilities already tested should allow a conventional macOS Wine design. Treat this as an implementation hypothesis until a Wine process runs; the platform test alone does not validate Wine's memory manager or loader.

No-Rosetta evidence must cover runtime processes and the build tools used for the POC. A universal executable is acceptable when it actually runs its ARM64 slice. An x86-64 Windows PE translated by FEX is expected. An x86-64 Mach-O translated by Rosetta fails the requirement.

## 3. Reference projects: Madeira and others

### 3.0 Selected sources (R1)

| Component | Selected source | Notes |
|---|---|---|
| Wine | Upstream `https://gitlab.winehq.org/wine/wine.git` (mirror `https://github.com/wine-mirror/wine`), tag `wine-11.19`, commit `455e3509b98a6919fd4ad1def4803e08c41c03b2` | Pin a tag, not master. Rebase deliberately every 2–4 development releases and re-run P0, M0, EM and later gates each time. Upstream CI builds macOS only as x86_64 and ARM64EC only on Linux, so native arm64 macOS regressions are this project's to catch. |
| FEX | Upstream `https://github.com/FEX-Emu/FEX.git`, main at or after `f18599d09` (e.g. `7d3090f78237`), or the first tag that contains it | FEX-2609.1 (`9fbdc00b`) is an off-main point release lacking the WoW64 CHPEv2 suspend/exception work. Build `arm64ecfex` and `wow64fex` as Windows PE with FEX's MinGW toolchain file. |
| DXMT | Upstream `https://github.com/3Shain/dxmt.git`, main at or after `e94c312` | v0.80 lacks `-marm64x` (3b78076) and hybrid_patchable (20af9fc). |
| LLVM/MinGW | A release newer than 20260421 (e.g. 20260908 or 20260922), verified as in P1.3 | Madeira's loader-ordering patches exist because ld.lld crashed on 20260421 when linking FEX without the MinGW CRT. |

No public Wine version contains this plan's macOS host work (4 KiB spawning, layout emulation, custom-x18 boundaries, TSO, MAP_JIT). Upstream master still links every Darwin build with `-pagezero_size,0x1000`. The local patch series therefore stays, rebased on the selected tag.

Rejected bases, with reasons: wine-11.0 stable (lacks the 11.x ARM64EC/WoW64 and macOS groundwork); Proton (Linux-only, 11.0 base); Hangover's Wine (Linux-only); Madeira's fork (11.4 plus iOS commits); CrossOver 26.x (x86_64/Rosetta; an arm64 build of its 26.3 tree reportedly fails to load kernel32 [unverified]); Wine MR11638 (reportedly unentitled, native-ARM64-only, relies on xnu's SDK&lt;13 x18 override, no 4 KiB pages or low 4 GiB, so no identity-mapped WoW64 [unverified: the MR was not reachable during review]).

### 3.0.1 Comparison references

Use these to diff design decisions, not as sources to copy wholesale. Their runtime results are self-reported and unverified here.

| Project | Snapshot | What it is | Use |
|---|---|---|---|
| [MacNeutron](https://github.com/chadouming/MacNeutron) | `8813ac1f982f` | Wine 11.19 + 20 patches, FEX + 5 patches, ARM64X DXMT; entitled, 4 KiB, strict x18 toggling, exec via SETEXEC. Requires macOS 27 and an Apple-granted entitlement; no ad-hoc mode | Closest public design. Diff each local patch area against it: dual-view EC code memory (its Wine 0011 + FEX 0005), RW↔RX fault flip (0006), winemac shim (0013), msync |
| [Highball arm64 line](https://github.com/himbeles/highball-engine-aoe4) | `f27fd69d2e45` | Wine 11.18 + 3 patches, Hangover FEX DLLs, a small Darwin FEX unixlib; reports i386 and x86-64 within ~20% of Rosetta on a compute loop on an M4, macOS 27. No renderer | Minimal-patch reference; Darwin FEX unixlib (`fex/fexunixlib_darwin.cpp`), fault flip (0019) |
| CrossOver ARM64 preview | Blog post 2026-07-31 | Native arm64 Wine, custom macOS FEX, ARM64 DXMT, macOS 26.5+, no D3DMetal | Diff its LGPL Wine sources when published; its FEX changes need not be published |
| [Hangover](https://github.com/AndreRH/hangover) | Wine 11.16 + 9 commits | Linux ARM64 Wine + FEX/Box64 | WoW64 patches as i386 references (d6a44ddebc, 6789030082, 594cf64e8b, 7b1ccaa862, 07defd3b97) |

Upstream FEX has no macOS plans and does not accept AI-generated contributions. Expect the macOS FEX changes (Darwin unixlib, JIT memory) to remain a downstream patch series.

### 3.1 Madeira assessment

[Madeira](https://github.com/willfaust/Madeira) is an iOS single-process runtime: the wineserver is a thread, Windows processes are pseudo-processes, and JIT memory comes from an attached debugger. About 115k lines of iOS replacement C under `build/` work around iOS limits that macOS 26.5+ removes: a hard 4 GB `__PAGEZERO` (hence offset-window WoW64), x18 zeroed on context switch (hence TEB in a TSD slot), no executable memory outside one pool, and no hardware TSO. Its DLLs are ABI-incompatible with an x18-based macOS Wine. **Use it as a reference only, never as a base.**

Harvest:
- FEX's DualMap write path in the ios-port-2607 fork, as a checklist of every place FEX writes code (80+ sites: `DualMap.h`, `Buffer.h` WritePtr, JIT link/backpatch writes, `Dispatcher.cpp`, `ArchHelpers/Arm64.cpp`). Invalidate the instruction cache at the **RX** address after writing through the RW alias. Licence: changes published before 2026-08-28 are MIT, later ones GPL-3+ (`LICENSE-MADEIRA.md`); prefer MacNeutron's port or a clean implementation.
- The sysctl-based CPU feature list and AFP/LRCPC2 tuning.
- Bug reports to reproduce on this runtime: `free_async_queue` use-after-free (d0c56b04eb) and the RtlIsEcCode bounds check (ac650deca3).
- The x64 instruction conformance tests (`asmconf-x64`, FEX golden tests re-hosted as a PE), rebuilt from source.
- Steam notes: SteamSetup and the bootstrap `steam.exe` are 32-bit; CEF flags; the Windows 8 version-lie that selects the legacy channel.

Avoid: the `build/*-unix` replacement runtime, pool execution and aliases, x18 avoidance, guest windows, software-only TSO, prebuilt `xtajit*.dll`, the ARM64EC loader-ordering patches (06143656ec, 948212bd97, f3339da9f6, a052a7f8e3), and the DXMT fork (defines `DXMT_IOS` for every Windows target, non-standard install directory, GPL-3 additions).

The remainder of this section is the original P1 inspection record. It is kept for traceability; where it conflicts with 3.0 and 3.1, those govern.

The inspected superproject snapshot is `bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120`. Its gitlinks and `.gitmodules` identify these candidates:

| Component | Repository | Snapshot commit | Candidate role |
|---|---|---|---|
| Madeira | `https://github.com/willfaust/Madeira.git` | `bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120` | Integration reference and test sources |
| Wine | `https://github.com/willfaust/wine.git` | `3a54f56896c85c932870afe6fd91404bbbcb74c8` | ARM64EC integration reference; possible source base |
| FEX | `https://github.com/willfaust/FEX.git` | `be778d7ba5b98bee0405fd1d6a50d305a0807df0` | Emulation integration candidate |
| DXMT | `https://github.com/willfaust/dxmt.git` | `8937c08c38f5cb867d995f99b2323739a9f6ffdf` | ARM64EC/Metal integration reference |
| Madeira Dock | `https://github.com/willfaust/madeira-dock.git` | `3cadfbea700e4da4b04e331dd7ef1ba633dfacef` | Optional later launch experiment |

The three runtime fork branch tips matched these gitlinks via `git ls-remote` during planning. Their full nested dependencies and builds have not been verified. These are candidate pins, not a validated runtime source manifest. Preserve them as a reference snapshot even if newer upstream revisions are selected.

### 3.2 Component-specific reuse decisions

| Component | Investigate/reuse | macOS adaptation boundary | Required decision evidence |
|---|---|---|---|
| Wine | ARM64EC dispatch and emulator interface; fixes supported by tests | Keep genuine process creation, server IPC, normal prefix setup, native framework calls | Diff against the fork's real upstream base; prove selected paths compile for Darwin |
| FEX | ARM64EC backend, WoW64 backend, CPU-feature handling, correctness tests | Replace or omit iOS-only JIT pools, app bridge hooks, process emulation dependencies | Map each emulator import/export and native host service to its provider |
| DXMT | ARM64EC PE build and bridge changes | Use Cocoa/macOS windows and Metal integration; verify all PE/native argument layouts | Compare fork with upstream macOS DXMT and identify minimal ABI changes |
| Tests | Small x64/x86, process, FP, memory, and graphics sources | Build from source with the chosen toolchain; remove app-specific paths | Explicit numerical/API oracle, supported dependencies, bounded execution |
| Madeira Dock | Separate experimental Steam launch route | Does not replace full Steam client/update/helper testing | Exact supported Steam client fingerprint and required authentication path |

Madeira's native Wine script selects `iphoneos`, substitutes several Unix-side sources, and statically registers Unix-call tables. This is evidence of a custom embedding layer, not a native macOS configure recipe. Trace each source replacement before considering reuse. [Inspected build script](https://github.com/willfaust/Madeira/blob/bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120/build/ntdll-unix/build.sh).

Its FEX ARM64EC build stages `libarm64ecfex.dll` as `xtajit64.dll`. Verify this convention against the selected Wine loader instead of assuming the filename alone establishes the interface. Build the PE backend and any native FEX support actually needed; do not assume the iOS FEXCore archive and the PE backend are interchangeable. [FEX backend recipe](https://github.com/willfaust/Madeira/blob/bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120/build/fex-arm64ec/build.sh).

Madeira's WoW64 design places 32-bit guest addresses in offset windows because of its host restrictions. On this macOS POC, investigate identity mappings below 4 GiB first. Importing the offset-window design would require pointer conversion throughout the runtime and should be a separately justified architecture change. [WoW64 design](https://github.com/willfaust/Madeira/blob/bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120/docs/WOW64.md).

Madeira's DXMT iOS notes describe UIKit adaptations, static archive integration, and changed cross-process handling. Prefer upstream's macOS implementation for the native graphics side; retain fork changes only when their ARM64EC role is demonstrated. The iOS notes and newer build record describe different PE configurations, so inspect actual headers/build outputs. [DXMT iOS notes](https://github.com/willfaust/Madeira/blob/bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120/build/dxmt-ios/README.md), [upstream DXMT](https://github.com/3Shain/dxmt).

### 3.3 Route selection gate

**Status (R1):** decided as route 1 with the sources in 3.0. Routes 2 and 3 are closed. The original gate text follows.

During P1, before its exit gate, write `docs/source-selection.md` with one selected Wine/FEX/DXMT combination and the following comparison:

1. **Preferred:** current verifiable macOS Wine support plus the smallest compatible FEX backend and upstream macOS DXMT. Use Madeira to supply missing ABI integration or correctness fixes.
2. **Alternative:** Madeira's Wine/FEX pair as a source base, with iOS embedding disabled and ordinary Darwin loader/server/process behavior restored. Select only if its host build paths and imports can be demonstrated rather than reconstructed from prose.
3. **Deferred:** porting Madeira's entire single-process app runtime. It introduces additional process, memory, UI, and lifecycle work and is unnecessary unless the first two routes fail for an identified reason.

The selected combination must have available source, explainable dependencies, and a concrete smallest executable test. Choose based on a configure/compile experiment and source inspection, not project popularity or the number of patches. If neither preferred route is viable, record the missing interface or upstream change; do not create a large speculative patch series.

Madeira's September build record reports missing inputs and several clean-build steps as unverified. Check availability at the pinned snapshot; do not assume the record's older unavailable-submodule warning still applies, or that a newer public branch proves clean reproducibility. [Build record](https://github.com/willfaust/Madeira/blob/bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120/docs/BUILDING.md).

## 4. Rules for the implementing model

Work on one numbered task and one failure at a time. Each task ends with an evidence report and a small reviewable diff. Do not start Steam or game debugging until the prerequisite test IDs pass.

1. Read this plan, `README.md`, and `docs/milestones.md`. Inspect `git status` before editing. Preserve the existing passing platform test.
2. Locate symbols and files with `rg` in the actual pinned source. Record file and symbol names before proposing modifications. Never invent source paths, configure options, helper functions, or commit hashes.
3. Distinguish **planned**, **source inspected**, **configured**, **built**, and **runtime passed**. A script existing is not a build; a build is not a runtime pass; a loader version string is not M0 acceptance.
4. Use the selected source's `configure --help`, CMake options, Meson files, and generated logs. Commands below are specifications or inspection examples unless labelled verified. Fill in source-dependent commands only after checking them.
5. Keep host and PE compiler settings separate. Do not export Windows-target `CC`, `CXX`, or `-target` flags across the native Darwin build.
6. Generate patches from actual changes with `git diff` or `git format-patch`. Verify syntax and `git apply --check` against a clean checkout of the exact base. Never handwrite placeholder hunks or fictional index lines.
7. Do not apply patches twice, modify an unrelated source checkout, reset user edits, or hide rejected hunks with a fallback `patch` invocation. Abort with a clear error when the expected base does not match.
8. Do not suppress implicit-function-declaration or pointer-conversion errors to make ABI code compile. Do not copy disabled assertions or compiler-warning suppression from Madeira without understanding the specific need.
9. New tests return nonzero on failed assertions, check API errors and thread exit codes, and have a timeout. Do not print a failure and return success. Compile source-controlled test programs rather than downloading unexplained executables. Preserve attribution and license headers when adapting external test or runtime source.
10. A skipped required test remains pending. If a failure is environmental, record the exact command and output. Diagnose the actual failure rather than labelling every launch error an entitlement problem.
11. Add a feature or workaround only with a failing reproducer and a test that passes after the fix. Keep a workaround opt-in if it affects behavior beyond that reproducer.
12. Update milestone status only from evidence. Finish each task by listing changed files, commands run, result, unresolved issue, and the next task. Do not claim a full phase complete while any required test is pending.

The earlier drafts failed because they mixed host and Windows targets, contained malformed patches, and declared completion without binaries or execution evidence. Do not restore those drafts.

## 5. Files, build isolation, and evidence contract

Keep the repository small. Use a configurable absolute `AOE2_WORK_ROOT` outside the repository for checkouts, build directories, installations, Wine prefixes, and run logs. Never use a runtime prefix belonging to another Wine installation.

Proposed tracked files are deliverables to create when their task starts:

```text
sources.lock.json                 exact verified URLs/revisions/nested dependencies
scripts/check-toolchains.sh       host and PE compiler discovery/inspection
scripts/fetch-sources.sh          explicit locked checkout acquisition
scripts/build-wine.sh             native and PE builds, separate output trees
scripts/build-fex.sh               selected backend and required host support
scripts/build-dxmt.sh              PE frontend and native Metal bridge
scripts/sign-runtime.sh           explicit executable list; verify signatures
scripts/run-probe.sh               isolated prefix, timeout, evidence capture
scripts/verify-no-rosetta.sh       executable and running-process evidence
patches/<component>/               real patches against a declared base
tests/<test-family>/              source, build instructions, expected result
docs/source-selection.md          selected route and discarded incompatible paths
docs/runtime-abi.md               Windows/native boundary and ownership contracts
docs/test-results.md              result index; detailed machine logs stay outside Git
```

The existing `scripts/test-platform.sh` and `tests/platform/` remain the verified P0 baseline. Do not add empty scripts to satisfy this layout.

Each result needs: test ID; UTC timestamp; host model/OS/build; SDK/compiler versions; exact source revisions and patch hashes; command; binary architecture and SHA-256; relevant environment/DLL overrides; prefix identifier; stdout/stderr; exit status or signal; elapsed time; expected result; observed result. A JSON result plus text log is suitable. Avoid recording Steam credentials or tokens. Manual gameplay tests additionally record settings, duration, participants' game versions, and observations.

Suggested runtime tests use 30-second deadlines unless a row specifies otherwise. The harness terminates only processes belonging to its test session, preserves their logs, and reports timeout as failure. Use a native Python or other verified ARM64 supervisor if the host lacks a suitable timeout command. Test fixtures under the work root may be deleted/recreated explicitly; never delete a shared Steam library or saves to reset a test.

## 6. P0 — preserve and extend host evidence

**Entry:** baseline `bfac0ac`. **Implemented:** `./scripts/test-platform.sh`. **Exit already met:** current smoke checks pass on this installation.

The existing test checks API acceptance and a small memory/register operation. It does not prove Wine compatibility. Extend it only when the relevant runtime work needs stronger diagnostics; keep the original cases independently runnable and passing.

| ID | Explicit test idea | Pass condition | Use |
|---|---|---|---|
| P0-BASE | Run the current script before toolchain/source work | All three child cases PASS; exit 0 | Required baseline |
| P0-MEM-FAULT | In an isolated child map two 4 KiB pages; protect page 2 read-only; verify writes to page 1 still work; deliberately write page 2 | Supervisor sees expected protection fault at the protected address; unexpected exit/fault fails | Stronger memory contract before M0 |
| P0-SPAWN | Spawn a child, then a grandchild with explicit 4 KiB attributes; report page size in each | Both report 4096; parent collects exact statuses | Diagnose launch propagation |
| P0-X18-SCHED | In assembly, use an x18 sentinel while custom mode is active and run a bounded arithmetic loop while other threads create scheduling pressure | Sentinel survives; custom mode exits before any ordinary macOS call | Preservation under scheduling, not proof a switch occurred |
| P0-X18-SIGNAL | Later, add a signal reproducer following the SDK's custom-mode handler transition rules | Safe handler entry/return and restored guest sentinel; no framework calls while custom mode is enabled | Required before relying on a new signal-boundary implementation |
| P0-TSO | Keep main/new-thread API checks; optionally add an assembly x86-style store-buffering litmus | API success is required; litmus violations under enabled TSO are a failure, absence is only supporting evidence | Do not claim a finite run proves ordering |
| P0-JIT | Native ARM64 child emits a function returning 42 into the selected JIT allocation; switches write/execute state legally and invalidates instruction cache; calls it; updates to return 43 and repeats | Exact values and successful protection transitions, without permanently writable/executable policy assumptions | Before FEX integration |

Mask signals in simple x18 tests. For a signal-aware test, inspect the installed `os/arch/arm64.h` contract first; x18 setters strictly toggle state and disabling custom mode destroys its guest value. Preserve that value on the guest side and let macOS restore its own register semantics. Never restore the guest TEB register into ordinary macOS code.

Do not add `os_cross_arch_is_supported()` to a mandatory 26.5 test; the installed SDK annotates that query as 26.6. API availability annotations and the Wine announcement differ: describe the required feature set as available by 26.5 rather than claiming every function was introduced in that release.

## 7. P1 — source acquisition, toolchains, and architecture decision

### P1.1 Reproduce the baseline and record tools

Run P0-BASE. Record `sw_vers`, `uname -m`, `xcode-select -p`, `xcrun --show-sdk-path`, `xcrun --show-sdk-version`, `xcrun clang --version`, and linker identification. Resolve actual executable paths and inspect `file`/`lipo -archs` for compiler, linker, Python, CMake, Ninja, Meson, and other invoked build tools.

A shell script's interpreter and native extensions matter too. Command Line Tools suffice for P0. Install/select additional Xcode/Metal tooling only when the selected source build requires it; do not claim a full Xcode installation is already present or always required.

**Output:** `docs/toolchains.md`, with commands actually run and missing tools.

### P1.2 Acquire reference sources without starting a full build

Fetch the Madeira superproject snapshot without recursive submodules or prebuilt app assets when possible; sparse/no-checkout acquisition is sufficient for inspection. Read `.gitmodules`, gitlinks, `docs/BUILDING.md`, relevant `build/` scripts, and test sources. Fetch only runtime repositories being compared, with nested dependencies when their source inspection/build needs them.

For each chosen SHA, prove the object is fetchable and that `git rev-parse HEAD` equals it. Record nested gitlinks too. Obtain the upstream base of each fork from actual history/remotes; do not diff unrelated tips and call all differences porting requirements.

Inspect current upstream Wine ARM64 macOS support and MR11638 or its successor commits. (R1: the upstream audit selected wine-11.19; see 3.0. MR11638 and the wine-devel announcement still need to be read and archived from a host that can reach winehq.org.) If GitLab access fails, preserve the error and compare available authoritative source; do not fabricate the inaccessible MR's contents. Inspect FEX backend source and upstream macOS DXMT as well.

**Output:** source evidence table: component, feature, source file/symbol, base/commit, existing behavior, host dependencies, action (`use`, `adapt`, `exclude`, or `unknown`). Unknown items remain unknown until inspected.

### P1.3 Verify both compiler families

Choose a macOS-hosted LLVM/MinGW release or a reproducible native source build. Madeira's documented release is a candidate to check, not a command to execute blindly. Verify asset existence, checksum, actual ARM64 execution, wrapper names, sysroots, headers, libraries, and ARM64EC support. The [LLVM/MinGW project](https://github.com/mstorsjo/llvm-mingw) provides release/source-build guidance; source builds use its actual documented scripts.

Compile these minimal artifacts into separate directories:

| ID | Target | Probe | Required evidence |
|---|---|---|---|
| TC-HOST | ARM64 Darwin | Print architecture and exit 0 | Mach-O arm64; executes natively |
| TC-A64 | Windows ARM64 | `GetCurrentProcessId`, then exit with known code | PE machine ARM64; imports resolve to expected runtime |
| TC-EC | Windows ARM64EC | Minimal EXE and exported-function DLL | PE/COFF and hybrid metadata match the ABI expected by selected Wine |
| TC-X64 | Windows x86-64 | Same simple Windows API probe | PE AMD64 |
| TC-X86 | Windows i386 | Same simple Windows API probe | PE I386; required before M2 |

Use `llvm-readobj`/equivalent to inspect headers, imports, exports, and ARM64EC metadata; `file` alone may not explain hybrid images. TC-A64/EC/X64/X86 compilation does not imply execution yet. Minimize CRT dependencies for the first runtime probe, or explicitly install the matching built Wine CRT modules. Never mix incompatible static CRT libraries just to resolve a link error.

### P1.4 Select source combination and issue the first build recipe

Complete section 3.3, write `sources.lock.json`, and record exact native/PE build commands after checking source options. Prefer configure-generated build rules over manually compiling dozens of Wine sources. If a custom rule is required, document its inputs and generated headers.

**P1 exit:** source objects and necessary nested dependencies are available; TC-HOST/A64/EC/X64 build checks pass; selected Wine host configuration succeeds; first ARM64 console build/run steps are concrete. TC-X86 may remain pending until M2. No claim of full source audit completion if ABI dependencies remain unknown.

## 8. M0 — execute Windows ARM64 code through native Wine

The implemented console profile uses Wine 11.4 base `cc893ef9cb17b994bfd1f1a1f7355be55e615623`
plus `patches/wine-m0/0001-native-arm64-macos.patch`. Reproduce with
`scripts/build-wine.sh` and `scripts/test-m0.py`. Build/VM decisions and actual
failures are recorded in `docs/source-selection.md` and `docs/m0-results.md`.

Six device drivers are deliberately disabled: NDIS, winebus, winebth, wineusb,
mountmgr and nsiproxy. Native Windows writable/executable heap commit fails on
this host and causes unchecked driver heap use to fault. Console M0 does not
validate those drivers, device enumeration, drive-management services or the
nsiproxy networking path. Do not run Steam on this profile or mistake their
absence for a working general Wine port.

The executable-memory contract is now specified in M0-EM. It replaces the
earlier requirement that every positive RWX probe pass natively.

### M0.0 Re-port onto wine-11.19 (R1, next task)

Wine 11.4 is 15 development releases and about 3,900 commits behind wine-11.19,
including about 100 ARM64/ARM64EC/WoW64 core commits that current FEX relies on
(cooperative suspend b8d8f34ffd/211e7a3d3b; KiUserEmulationDispatcher rework
f12bd89a4b, d3b41a854a, 3b6b0cedd9, 56ba8d233c; EcCodeBitMap bounds check
2f69c014dc; dispatcher rework fc2ba3ffce, 6ddac4544f, 27da578141) and macOS
groundwork (356547ea6e SIGBUS as SIGSEGV; 321d527d84/920240e73e CPU features and
name; 8ad6011269 address-space limit; fd3fbe3ef3 macOS main-thread handling;
1a63b0d7c4 cross-process Metal swapchain).

11.4 also has a latent bug in this exact configuration: `server/mapping.c`
rejects view addresses not aligned to the server's 16 KiB mask, which breaks
4 KiB clients. ed091c479a (wine-11.9) fixes it. If the re-port is delayed,
back-port that commit to the 11.4 profile first.

Re-port procedure:

1. Fetch wine-11.19 from upstream (not the willfaust URL) into a new checkout
   `sources/wine-r1`; keep `sources/wine-m0` unchanged for comparison.
2. Re-implement the M0 patch by hand. A dry run rejected 7 hunks in each of the M0
   and EM patches: `configure`/`configure.ac` (preloader context changed by
   dee9173b15, c2aaafcf10, f82008b27b), four places in `signal_arm64.c`
   (`call_user_mode_callback`, `ill_handler`/`bus_handler`, `signal_init_process`,
   `__wine_unix_call_dispatcher`) and `virtual.c`. Hunks that apply in the dispatcher
   land in changed code (new `_kernel_stack`/`_user_stack` labels, a second
   `syscall_dispatcher_return_slowpath`, `usr1_handler` PC rewrite); review them as
   carefully as the rejects. Drop only the SIGBUS hunk, which upstream supersedes.
   Re-check the low reservation against 60c5ce0263 and 4c18d96e9b.
3. Fix these defects during the re-port (M0.0.1).
4. Produce `patches/wine-r1/` as a reviewed series (one concern per patch: build
   and layout, 4 KiB exec, x18 boundaries, signals, TSO, diagnostics, executable
   memory), not one combined diff.
5. Pass P0-BASE and all 32 M0 checks on the new base before any further EM work.
   Keep the 11.4 profile buildable until then.

#### M0.0.1 Defects to fix in the re-port

| ID | Defect | Required change and test |
|---|---|---|
| R1-X18-RACE | A signal arriving after `MACOS_ENTER_GUEST` but before the switch to the user stack is classed as inside a syscall, so custom mode is not restored. The x18 setters are strict and trap when called with the current state; with custom mode off the kernel zeroes x18 on exception return, so the next leave-guest call traps or the guest TEB is lost. Found by code reading; upstream fc2ba3ffce changes the same window. | Define the boundary state from one authoritative per-thread flag that the signal path reads, not from the stack position. Add a stress test that delivers timer signals (SIGALRM/SIGUSR1) at high frequency while guest threads make syscalls and Unix calls in a tight loop, for 60 s, checking guest TEB and exit status. |
| R1-HOTPATH | `getenv` runs on every transition when `AOE2_M0_DIAGNOSTICS` is unset, `sysconf` runs on every transition, and `getenv` runs in `system_time_precise`. `test-m0.py` always sets the variable, so the release path is untested. | Read configuration once at process start. Run the M0 suite with diagnostics both on and off. |
| R1-SPAWN | The 4 KiB re-spawn leaves a waiting 16 KiB parent per Windows process, forwards no signals and reports `128+N` exit codes. | Use `posix_spawn(POSIX_SPAWN_SETEXEC)` with `posix_spawnattr_set_4k_page_size_np` in the loader and in ntdll's exec path (Wine already uses SETEXEC in `dlls/ntdll/unix/loader.c`). Check for the entitlement first: an unentitled 4 KiB exec is a silent SIGKILL. Test that a signal sent to the Windows process's host PID reaches it and that exit codes are exact. |
| R1-TSO | `thread_set_x86_64_compat(1)` is called on every thread, including pure ARM64 processes, and FEX is never told hardware TSO is on, so it still emits software barriers. | Enable TSO only in processes that load an x86 emulator, and only on threads that execute translated code. Report it to FEX through the Darwin unixlib (M1.1). |
| R1-CPUID | `get_core_id_regs_arm64` is a stub outside Linux (`dlls/ntdll/unix/system.c`). FEX reads zero ID registers and assumes ARMv8.0 without LSE. | Synthesize ID register values from `hw.optional.arm.FEAT_*` sysctls. Test: an ARM64 probe reads the registry/`IsProcessorFeaturePresent` values and they match the sysctls. |

### M0-EM Executable memory contract (replaces EM-3/EM-4 exit criteria)

Facts this design rests on (see `docs/route-review.md` section 4 for sources):

- xnu refuses any simultaneously writable and executable mapping that was not
  created with `MAP_JIT` (`VM_MAP_POLICY_WX_FAIL`). No entitlement changes this.
  EM-1's EACCES is permanent; "native RWX at the same address via mprotect" is
  not a goal.
- `MAP_JIT|MAP_FIXED` is allowed for arm64 4 KiB non-"exotic" maps since
  xnu-12377.101.15 (macOS 26.4), and the cross-architecture entitlements grant
  MAP_JIT. Whether layout emulation counts as "exotic" is closed source and must
  be tested. `docs/executable-memory.md` cited the frozen xnu `main` branch
  (26.0); cite release tags instead.
- MAP_JIT write permission is per thread; a toggle made inside a signal handler is
  reportedly lost on return; mprotect on a MAP_JIT range reportedly fails once it
  is RWX; hardened runtime may limit a process to one MAP_JIT region [all unverified].
- FEX itself allocates its code buffers, dispatcher and trampolines with
  `PAGE_EXECUTE_READWRITE` (`AllocatorHooks.h`, `SharedCodeBufferManager.cpp`,
  `ARM64EC/Module.cpp`, `WOW64/Module.cpp`) and toggles
  PAGE_EXECUTE_READ/READWRITE in its invalidation tracker. Failing these requests
  (EM-2's policy) breaks FEX initialization.

Design, by consumer:

| Consumer | Host mapping | Windows-visible result |
|---|---|---|
| x86 guest memory in emulated processes (non-EC_CODE memory in ARM64EC processes; all guest memory under WoW64) | Exact read/write permissions, never PROT_EXEC. FEX's self-modifying-code write traps rely on the write permission being exact. | Requested PAGE_EXECUTE_* protection, recorded in Wine's metadata; never fails |
| FEX code cache, ARM64EC | One section mapped twice at a constant offset: RW view and RX view (MacNeutron Wine 0011 + FEX 0005 as references); or one large MAP_JIT region toggled per thread via the Darwin unixlib | PAGE_EXECUTE_READWRITE succeeds |
| FEX code cache, WoW64 | Same mechanism; FEX must request the pool explicitly (small FEX patch) or Wine uses an address rule (FEX allocates top-down; guest memory stays below 4 GiB; Hangover d6a44ddebc keeps WoW64 host allocations above 4 GiB) | As above |
| Native ARM64 code requesting RWX (ARM64 PE programs, ntoskrnl heap) | RW↔RX flip on fault (references: Highball 0019, MacNeutron 0006). Known risk: livelock when code stores into the page it is executing; detect and fail loudly | PAGE_EXECUTE_READWRITE succeeds |
| ntoskrnl driver heap | Make `ntoskrnl_heap` non-executable on aarch64 macOS (as in 458eb1a481 and dappermint 88ca5b254b) | Restores the six drivers without RWX |

Bring-up order:

1. EM-R1: non-executable ntoskrnl heap; restore NDIS, winebus, winebth, wineusb,
   mountmgr and nsiproxy; fresh-prefix startup with no unhandled exceptions.
2. EM-3 host experiments in an entitled, layout-emulated 4 KiB child, on 26.6.2
   and later on 27, under the target signing profile (S1): `MAP_FIXED|MAP_JIT` at
   Wine-chosen low addresses; a dual-view section; RW↔RX flip throughput;
   cross-core instruction-cache publication (writer thread on one core, executor
   on another, 10^6 iterations, no stale execution).
3. EM-4a: the fault flip for native RWX and the guest-memory policy. This is the
   cheapest way to unblock M1 (it reportedly let unmodified Hangover FEX run).
4. EM-4b: the dual-view or MAP_JIT code cache, as the performance and robustness
   target, before M1.6 and before performance work.

EM exit (replaces "all existing positive executable probes"): A64-EXEC-HEAP passes;
A64-EXEC-RWX passes through the flip; the six drivers start cleanly; host
mappings never have W and X together; Windows-visible protections match requests;
no reservation leaks. EM-2's ACCESS_DENIED behaviour remains only as the
fallback when a mechanism is unavailable, and must be logged.

### M0.1 Build the native host and minimum Windows modules

Configure out of tree with Darwin host compiler settings. Configure Windows targets through the pinned Wine source's actual PE compiler mechanism. Discover the produced loader name/path; do not assume `wine64` exists. Build the selected Wine server and minimum module set needed for prefix initialization and the probe. Capture `config.log`, generated options, full build output, and final file types.

First use an unmodified build to identify the earliest real failure. Apply only audited upstream changes or one focused fix supported by a reproducer. If the source already supports ARM64EC, do not add a duplicate configure implementation.

### M0.2 Implement the platform boundaries that are actually missing

Audit each row in the real source and record whether already implemented:

| Boundary | Required implementation behavior | Mistakes to avoid |
|---|---|---|
| Process startup | Wine client enters a 4 KiB process before code assuming Windows page semantics executes | Reporting 4096 while the kernel still uses 16 KiB |
| Child startup | Every relevant launch route explicitly requests required page mode | Assuming children inherit all compatibility state |
| Address space | Actual loader reserves appropriate space and maps Windows low regions without destroying live images | Copying the probe's `MAP_FIXED` into arbitrary occupied regions |
| x18 | Set guest TEB only in custom mode; save guest state and leave custom mode before Unix/framework calls; restore on return | `-ffixed-x18` alone, framework calls in custom mode, unconditional setter calls |
| Signals/exceptions | Correct guest/native boundary state and context restoration on fault/return | Copying iOS register rewriting without its runtime contract |
| Thread startup | Initialize compatibility state inside each executing guest thread | Setting TSO in the creator and assuming inheritance |
| TSO | Explicitly initialize threads that execute translated x86 code; inspect behavior for ARM64-only stage | Calling an API without checking failure |

The current platform probe links with `-Wl,-x86_64_layout_emulation -Wl,-pagezero_size,0x100000000`. Use it as the starting experiment for the actual executable that owns the address space, not a blanket dylib linker flag. The earlier `0x170000000` value failed locally; do not reintroduce it without testing a different verified toolchain/loader contract.

The launcher itself may run with ordinary page size and spawn a 4 KiB Wine child. Record which processes require the mode; do not guess that every helper or wineserver must be identical.

### M0.3 Sign and launch reproducibly

After final linking/modification, ad-hoc sign every relevant Mach-O executable with the entitlement where the selected path requires it. Verify signatures and inspect embedded entitlements. Track the executable list and reasons; do not sign PE DLLs as though they were Mach-O binaries. Re-sign changed artifacts before retesting.

Use a fresh M0-only prefix and explicit paths to the selected loader, server, and libraries. Prevent fallback to Homebrew/CrossOver/system Wine. A minimal `.app` layout may be used if actual runtime behavior requires it, but a placeholder bundle is not a milestone.

### M0.4 Required tests

| ID | Action | Exact oracle |
|---|---|---|
| A64-HELLO | Call Windows PID/TID APIs, write a fixed line, exit 23 | Exact line and loader propagates exit 23; PE is ARM64 |
| A64-MEM | `VirtualAlloc` 8192 bytes, change only page 2 protection, query both pages, free | Correct per-page protection/status; writes to page 1 survive; intentionally prohibited access is caught by a separate tested exception fixture |
| A64-SHARED | Read selected USER_SHARED_DATA fields through a source-verified Windows layout at `0x7ffe0000` | Address mapped, clock fields sane/advance, no access fault; not merely an unrelated scratch mapping |
| A64-THREAD | Eight workers, each keeps unique TLS data and increments a shared counter with `InterlockedIncrement` 10,000 times | Counter 80,000; TLS values stay distinct; every thread exit code and wait succeeds |
| A64-CALLBACK | `EnumSystemLocalesEx` invokes a Windows callback; the precise-clock Unix entry with opt-in native diagnostics exercises a native Unix round trip | At least one locale callback and successful enumeration; Unix round-trip returns expected value; guest TEB consistent before/after; native custom mode disabled |
| A64-SEH | `RaiseException` with an application code, then a deliberate access violation at known address; an additional process leaves the access fault unhandled | Handler receives exact codes/context; handled process continues; unhandled process terminates with status 5 and the expected fault address (interactive debugger disabled only for this negative fixture) |
| A64-IO | Unicode filename with spaces; write/read known bytes; delete | Exact byte comparison, all API results checked |
| A64-REPEAT | Run A64-HELLO 20 times from one prefix, then once from a fresh prefix | Every exit 23, no hung client/server or stale startup failure |
| HOST-NATIVE | Inspect executed host binaries, loaded native libraries, and live process architecture | No running Mach-O x86-64 translation; server/loader identity matches selected installation |

For SEH, first prove the selected Windows compiler supports the test syntax. If `__try` is unavailable, use supported compiler extensions or a vectored-exception test with a carefully defined continuation; do not silently drop SEH coverage or use ordinary C++ exceptions as its replacement. Keep intentional fault tests in separate processes.

**M0 exit:** all required A64/HOST tests pass with preserved evidence. ARM64 console execution is the first concrete runtime goal; it does not prove x86-64 translation.

## 9. M1 — ARM64EC and FEX x86-64 execution

### M1.1 Write the ABI map before integrating

Document `docs/runtime-abi.md`: Wine's emulator DLL discovery, machine type, required exports, initialization, ARM64EC call/return dispatch, Unix-call mechanism, exception/context interface, TLS/TEB ownership, CPU-feature source, JIT allocator/cache invalidation, and thread lifetime. Name the exact symbols from source and their providers.

Inspect Madeira's backend recipe and the corresponding pinned FEX implementation. Decide whether the PE module alone supplies the translator or needs host archives/hooks; record the evidence. Do not statically link two independent FEX runtimes merely because Madeira produces two categories of build output.

Build a native/PE backend combination compatible with M0. Identify actual imports and resolve them through the selected Wine runtime. Handle Darwin VM/protection, instruction-cache invalidation, signal handling, and thread contexts with focused reproductions. Hardware capabilities must be queried accurately for this Mac; do not hardcode a CPU feature mask copied from an iPhone.

R1 requirements, established by source review:

- **Backend selection.** Upstream Wine loads the x86-64 emulator named by `HKLM\Software\Microsoft\Wow64\amd64` (`dlls/ntdll/loader.c:load_arm64ec_module`) and the i386 emulator named by `Wow64\x86` (`dlls/wow64/syscall.c:get_cpu_dll_name`). The value must be a short bare DLL name resolved from system32. Install `libarm64ecfex.dll` and `libwow64fex.dll` under their own names and select them through these values; do not rename them to `xtajit64.dll`/`xtajit.dll` or patch the loader. FEX's `libarm64ecfex.def` matches the 20 exports in Wine's `xtajit64.spec`.
- **FEX build.** Rewrite `scripts/build-fex.sh` for upstream FEX: use FEX's MinGW toolchain file with `MINGW_TRIPLE=arm64ec-w64-mingw32` (ARM64EC backend) and `aarch64-w64-mingw32` (WoW64 backend). The current script configures for the macOS host, targets Madeira's fork and does not build `wow64fex`.
- **Darwin FEX unixlib.** Upstream FEX's PE backends call an optional unixlib (`Source/Windows/Common/FEXUnixLib.cpp`, gated on `Available()`); its Linux implementation does not apply to macOS. Highball reports SIGKILLs from raw Linux syscalls without a Darwin helper [unverified]. Treat a Darwin unixlib as required from day one: hardware TSO state, JIT write toggling if MAP_JIT is chosen, and any host queries FEX needs. Reference: Highball `fex/fexunixlib_darwin.cpp`.
- **TSO.** Tell FEX that hardware TSO is active on the threads where it is enabled, so it stops emitting software barriers; verify with a FEX log or a store-buffering litmus throughput comparison.
- **CPU features.** Depends on R1-CPUID (M0.0.1).
- **JIT memory.** Depends on EM-4a at minimum (M0-EM). Do not enable FEX with EM-2's fail-on-RWX policy.
- **Floating point.** Run FEX with `X87ReducedPrecision=0` for any test that compares results with Windows, and for M5 multiplayer.

### M1.2 Prove mixed execution and backend selection

Create a Windows ARM64EC DLL exporting a simple integer operation and an x86-64 caller. Have each print/check its expected architecture-specific behavior and a known result. This verifies call/return dispatch rather than just loading a DLL.

Collect Wine module-loading evidence and at least one backend-specific initialization/execution diagnostic or trace from the selected FEX source. In an isolated prefix, make the backend unavailable: the same x64 probe must fail to execute. Restore it and rerun. A successful hello with no backend evidence is insufficient.

### M1.3 Required tests

| ID | Action | Exact oracle |
|---|---|---|
| X64-HELLO | Rebuild the ARM64 hello source as AMD64 and execute | Exact text/exit 23; backend evidence present |
| EC-CALL | x64 caller calls ARM64EC DLL with integers, pointers, doubles, and callback; repeated 10,000 times | Exact integer/data/callback results; FP checks use explicit tolerance; no stack corruption |
| X64-ALU | Fixed assembly vectors for shifts, carry/overflow, signed division, compare/branches | Exact registers/flags against checked-in expected values |
| X64-FP | SSE2 arithmetic/conversion plus selected x87 cases where emitted; rounding modes and NaN cases | Correct specified result/classification; compare with a trusted Windows run where semantics are subtle |
| X64-THREAD | Reuse TLS/atomic worker test; exercise compare-exchange and event handoff | Exact counters/TLS and no deadline failure |
| X64-EXCEPT | Raise application exception and deliberate translated-code faults; capture context | Correct Windows code and guest instruction address, valid unwind/handler behavior |
| X64-SMC | Allocate guest code returning 1, execute, change to return 2, call `FlushInstructionCache`, execute; repeat 100 times | Current value every time; stale translated blocks fail |
| X64-PROTECT | Change protection on one guest 4 KiB page and query it; fault fixture exercises forbidden access | Windows-visible protection and exception addresses correct |
| X64-STRESS | 20 consecutive launches plus four concurrent isolated probes | All statuses/results correct, no translation deadlock or monotonically leaked runtime process count |
| X64-BACKEND | Backend present/absent/restored experiment | Success/failure/success, with expected backend diagnostic |
| X64-ASMCONF | FEX's golden x86-64 instruction tests re-hosted as a Windows PE (Madeira's `asmconf-x64` approach), built from source | All cases match expected results; listed exceptions documented individually |
| WINETEST-X64 | Selected Wine conformance test modules (at least ntdll, kernel32, kernelbase) built as x86-64 and run under FEX | No regressions against the same modules in the ARM64 lane; failures triaged individually |

Reuse Madeira's `tests/x64/asmconf-x64.c`, `fpconf-x64.c`, `setjmp-x64.c`, `heap-x64.c`, and `fileio-x64.c` selectively after inspecting their expected behavior and dependencies (GPL-3 where marked; preserve licences). The existence of those tests or text-based host checks is not evidence they pass here. [Reference test directory](https://github.com/willfaust/Madeira/tree/bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120/tests/x64).

**M1 exit:** ARM64EC mixed calls and required x64 tests pass; FEX selection and no-Rosetta execution demonstrated. Keep graphics and Steam out of failure reproduction.

## 10. M1.5 — genuine process and runtime integration

This gate is deliberately stricter than a single translated executable. Steam requires process separation, IPC, synchronization, callbacks, and repeated lifecycles.

| ID | Action | Exact oracle |
|---|---|---|
| PROC-CHILD | x64 parent uses `CreateProcessW` with arguments containing spaces/Unicode, environment marker, redirected pipes, child exit 37 | Child sees exact arguments/marker; parent receives output and exit 37 |
| PROC-MIXED | Later run x64 parent -> x86 child and x86 parent -> x64 child | Correct child architectures and statuses; required before M2 |
| PROC-ISOLATION | Two children reserve the same guest address, store different patterns, synchronize with parent | Both retain their own pattern; distinct host tasks in selected process model |
| PROC-IPC | Parent/child share a named mapping, exchange messages over a named pipe, signal named events | Exact transferred bytes/counter; proper wait and close behavior |
| PROC-RESTART | Terminate one fixture child, restart it, run another normally | Other child survives; restart works; no stale shared handles |
| SYNC-WAIT | Event, mutex, semaphore, wait-many, timeout, abandoned mutex cases | Exact Windows wait result for each scripted case |
| NET-LOCAL | Windows client TCP/UDP fixtures talk to native loopback server | Exact payload, timeout and orderly-close behavior |
| NET-TLS | Windows WinHTTP HTTPS fixture fetches a fixed controlled endpoint and performs a deliberate certificate-error case | Success status/expected data, correct rejection in negative case; no disabled validation workaround |
| PREFIX-CLEAN | Build/run from clean source outputs and a fresh prefix, then repeat after ordinary shutdown | Same results and source identity; no dependence on an old installation |
| ABI-BOUNDARY | Sample guest, Unix callback, native worker, and signal paths in debug build | Page/TEB/x18 state and per-thread TSO initialization result recorded at relevant points; no forbidden custom-mode macOS calls; do not invent a TSO getter |

Do not treat a host PID printed by a pseudo-process runtime as sufficient proof of Windows process isolation. The isolation and IPC tests must demonstrate the selected architecture's semantics.

**Exit:** required process/synchronization/network tests pass. PROC-MIXED waits for M1.6's x86 probe. Any session cleanup must preserve unrelated Wine processes and user data.

**Synchronization performance (R1).** Upstream Wine's in-process synchronization (ntsync) is Linux-only, so on macOS every wait is a wineserver round trip. Measure it with a SYNC-PERF fixture (uncontended event set/wait and mutex acquire/release, 10^6 iterations, single and 8 threads) and record the numbers. If it dominates later profiles, evaluate CrossOver's msync (carried by MacNeutron) as a separate patch with its own tests.

## 10.1 M1.6 — i386 guests through WoW64 (R1)

32-bit x86 support is part of the end goal, not only a Steam prerequisite, so it gets its own milestone before M2.

Build and configuration:

- Configure Wine with `--enable-archs=arm64ec,aarch64,i386` and build upstream FEX's `wow64fex` (aarch64 PE). Select it via `Wow64\x86`.
- WoW64 FEX code cache uses the M0-EM mechanism (EM-4b), with an explicit pool request or the top-down address rule; guest memory stays identity-mapped below 4 GiB.
- Test that [64 KiB, 4 GiB) is reservable for large-address-aware i386 programs. Highball reports that a `0x170000000` layout works [unverified], whereas this host recorded a failure with that value; retest with the re-ported loader before choosing.
- Use Hangover's WoW64 commits (3.0.1) as references; take only changes with a reproducer here.

Required tests:

| ID | Action | Exact oracle |
|---|---|---|
| TC-X86 | Build the simple Windows API probe as i386 | PE I386 |
| X86-HELLO | Run the hello probe as i386 | Exact text, exit 23, `wow64fex` loaded |
| X86-MEM / X86-THREAD / X86-SEH / X86-IO | i386 versions of the A64 memory, TLS/atomic, exception and file probes | Same oracles as the A64 tests |
| X86-LAA | Large-address-aware probe reserves and touches memory above 2 GiB and up to the 4 GiB limit | Expected addresses succeed; no collision with host allocations |
| X86-SUSPEND | Suspend/resume and GetThreadContext on a thread running translated i386 code, 1,000 times | Contexts are valid i386 contexts; thread completes correctly |
| X86-UNIX | x86 code calls into native Unix code with pointer-bearing structures (e.g. a file or socket API path) | Null pointers, handles, lengths and padding keep their meaning |
| X86-CONCURRENT | Two concurrent i386 processes use the same low address with different data | Each keeps its own data |
| PROC-MIXED | x64 parent → x86 child and x86 parent → x64 child | Correct child architectures and statuses |
| WINETEST-X86 | Same Wine test modules as WINETEST-X64, built as i386 | No regressions against the ARM64 lane |

**M1.6 exit:** all of the above pass. The only public i386-under-FEX-on-macOS data point is a compute loop, so expect real work here.

## 11. M2 — the real Windows Steam client

### M2.1 Establish required architecture support

Inspect PE headers of the actual Steam installer/client/helper files acquired for this test. Record client build and architecture per executable; do not assume Steam is all x64 or assume Madeira's client pins match the current download.

M1.6 must pass first; it covers the WoW64 build, backend selection and i386 tests. Identity low-address mapping is the design; an offset window like Madeira's is not needed on macOS 26.5+ and would require a separate pointer/handle/ownership design. Madeira reports that SteamSetup and the bootstrap `steam.exe` are 32-bit; confirm from the actual files.

### M2.2 Steam smoke sequence

Use a separate Steam prefix. Record exact runtime pins and client build. Let the official client perform authentication; user interaction may be necessary for credentials/Steam Guard. Do not automate credential capture or put tokens in run logs.

1. Install and start the genuine Windows client; capture process tree and first failure.
2. Reach login, authenticate, and restart once to check persistence.
3. Display Library and Store; verify text, fonts, scrolling, and window/input behavior.
4. Download a small owned application or test target; pause/resume and verify completion.
5. Launch it through Steam; check that process exit is observed and Steam returns to idle.
6. Restart Steam three times; exercise a helper restart in an isolated session; check server/process cleanup.
7. Record updater behavior and one update if available. If no update is available, mark the update test pending rather than passed.

**M2 exit:** installation/login/UI/download/test launch/restart pass without Rosetta; required helpers and architectures accounted for. A broken Store or web helper is a named compatibility gap even if launching a title becomes possible.

### M2 optional: Madeira Dock

Dock is a distinct experiment if the full Steam UI becomes the dominant obstacle. It uses client-internal interfaces tied to supported fingerprints and starts installed games without the desktop/web-helper UI. Its documentation does not establish compatibility with the client acquired here or AoE2DE multiplayer. [Dock design](https://github.com/willfaust/Madeira/blob/bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120/docs/MADEIRA_DOCK.md).

Before adapting it: inspect the pinned Dock source, supported client layout hashes, normal authentication flow, and installed-content requirements. Test supported-client launch, unsupported-client refusal, missing-ownership refusal, actual game Steam API initialization, callbacks, online presence, and repeated shutdown. Preserve normal client license checks.

A Dock result must be reported as a separate launch path. It cannot mark the full-client M2 acceptance complete. If adopted for a narrower game-only POC, explicitly document the scope change and still require M3–M5, including matchmaking and simulation tests. Do not change the objective silently to “launch the EXE.”

## 12. M3 — DXMT D3D11 and AoE2DE menu

### M3.1 Build graphics in the selected ABI

Inspect [DXMT's macOS build instructions](https://github.com/3Shain/dxmt/blob/main/docs/DEVELOPMENT.md), then pin the chosen source. Identify the actual D3D11/DXGI/Metal bridge outputs and their dependencies. Build native pieces for ARM64 Darwin and Windows pieces for the ABI that M1 proves can interoperate with the x64 application.

Write down every PE-to-native bridge argument layout, pointer size, handle representation, structure packing, lifetime/ownership rule, callback, and thread requirement. Borrow Madeira's ARM64EC changes only where that contract matches; keep macOS window/swapchain behavior. Do not port UIKit or iOS static table registration into the native Mac path without need.

The inspected upstream build instructions require LLVM 15 libraries and Xcode/Metal tooling; verify these against the selected commit. DXMT shader-conversion LLVM libraries are a separate dependency from the LLVM/MinGW compiler used for Windows PE files. Build/link the former for ARM64 Darwin, and inspect every native archive/library. Do not follow an x86-64 LLVM or Rosetta-shell example from older build documentation. Require a native shader-conversion smoke test before the D3D11 device test.

Use explicit DLL overrides only for this test prefix. Record loaded module paths/hashes. Confirm DXMT actually supplies the device and Metal is used, rather than a different Wine renderer or software fallback.

R1 graphics requirements:

- **Source and build.** Upstream DXMT main at or after `e94c312`, built as ARM64X PE plus i386 PE, with an aarch64 `winemetal.so` linked against an arm64 build of the LLVM version DXMT requires (15.0.7 at review time). Rewrite `scripts/build-dxmt.sh`, which targets Madeira's fork.
- **winemac shim.** DXMT needs winemac.drv's `macdrv_functions` export (or the hidden symbols) and the Wine 8 `macdrv_win_data` layout; without them it aborts at `d3d11_swapchain.cpp:138`. Add a small winemac patch exposing them. References: CrossOver's `d3dmetal.c` (x86_64-guarded there), MacNeutron 0013, dappermint 713015f/13e6a88/565f638. Track DXMT PR #166 and Wine MR 11058 (ExtEscape) as the long-term replacement [unverified].
- **G0 Metal probe**, before D11-DEVICE: a native Metal device, command queue, buffer and compute dispatch created from a Unix call inside the 4 KiB, custom-x18, layout-emulated Wine process, with a readback oracle. This separates Metal-in-this-process problems from DXMT problems.
- **i386.** Test `newBufferWithBytesNoCopy` on 4096-aligned memory below 4 GiB before relying on DXMT for i386 games.
- **Per-application use.** Steam's CEF/ANGLE has open DXMT bugs (#141, #183); apply DXMT per application, not prefix-wide, until those are tested. Cover cross-process CEF swapchains and D2D/IDXGISurface interop (DXMT PR #222 open at review time) before M2's UI tests rely on them.
- **Other APIs.** D3D9 order to evaluate: wined3d, then mtld3d (zlib licence), then DXVK on KosmicKrisp. DXVK on MoltenVK is ruled out (MoltenVK lacks geometry shaders, nullDescriptor and robustBufferAccess2, which DXVK 2.x requires). D3DMetal is ruled out (x86_64-only, evaluation licence).
- AoE2DE has no public DXMT reports; check D2D text rendering early.

### M3.2 Required standalone rendering tests

| ID | Action | Exact oracle |
|---|---|---|
| D11-DEVICE | D3D11 device and swapchain creation from x64 guest; record adapter and feature level | Required HRESULTs succeed; backend/module evidence and usable feature level |
| D11-CLEAR | Clear offscreen RGBA8 target to known color; copy to staging; map/read | Expected pixel bytes within format-defined conversion tolerance |
| D11-TRIANGLE | Render known triangle using checked-in DXBC shaders; capture/read pixels | Interior pixel matches expected color; exterior matches clear color |
| D11-BUFFERS | Dynamic vertex/constant buffer map/unmap and update every frame | Readback/current-frame output changes as expected, without stale data |
| D11-TEXTURES | Upload patterned textures, sample with known filtering, generate/use mips | Selected pixels match expected values/tolerance |
| D11-BC | Exercise compressed texture formats confirmed in game assets | Correct sampled colors; format support/unsupported results explicitly recorded |
| D11-RESIZE | Resize/minimize/restore 20 times; switch windowed/borderless | No device-loss hang; present and input recover |
| D11-LIFETIME | Recreate device/swapchain 10 times; render for 10 minutes | No crash/deadlock; GPU completion correct; memory settles after warm-up |

Use source-generated shaders or checked-in small test DXBC with reproducible generation instructions. Avoid depending on game shaders to debug the first triangle. A screenshot is supporting evidence; readback gives the numerical oracle.

### M3.3 AoE2DE menu

A native macOS AoE2DE build without Windows crossplay reportedly exists since 2026-05-28 [unverified]. Confirm that Windows Steam in this prefix downloads the Windows depot, and that the Windows build is the one matchmaking with Windows players.

Install the owned game through the validated Steam path. Record its actual app ID from Steam metadata, build/depot version, executable architecture/hash, imports, launch arguments, and runtime prerequisites. Install only dependencies identified by game manifests/import failures; do not apply a broad untracked winetricks recipe.

Reach the menu; verify animated rendering, fonts, mouse/keyboard, audio, settings, and normal exit. Run three cold launches. If the game fails, reduce to the relevant Windows API, graphics resource, media, or CPU instruction reproducer before altering the whole runtime.

**M3 exit:** standalone D3D11 tests and three stable game-menu launches pass, with DXMT/Metal and no-Rosetta evidence.

## 13. M4 — single-player behavior and performance

Define the test configuration before tuning: Mac model/chip/RAM, power mode, display scale/resolution, game settings, game build, scenario/replay file, duration, and measurement method. Select a realistic target with the user; do not claim “native-feeling” without numbers.

Use a repeatable built-in benchmark or a recorded representative replay if the installed build supports one. Otherwise define a fixed scenario, civilization/map/player count, scripted observation interval, and repeat three runs. Keep runtime pins constant within a comparison.

Required functional cases:

- Start a skirmish/tutorial and play for 30 minutes; verify camera, selection, commands, hotkeys, zoom, UI, and pathfinding progression.
- Save, quit, reload, and verify expected game state; preserve the fixture save separately.
- Exercise music, effects, speech, and an available video sequence. Missing media is an identified dependency, not fixed with a null audio driver.
- Switch focus/window mode, resize, change resolution, reconnect an input device if applicable, and return to play.
- Run a larger late-game scenario/replay; test memory pressure and resource churn; stop normally and relaunch.

Record FPS/frame times with the actual available tool; report median and p95/p99 when samples allow, warm-up policy, CPU translation utilization, GPU activity, memory, and stutter events. Synchronize measurement intervals with scenario time. A menu FPS counter is not gameplay evidence. Compare with an ARM64 graphics fixture to separate translation from GPU bottlenecks; use an optional known-good Windows run as a behavior reference, not a prerequisite host runtime.

**M4 exit:** three repeatable functional/measurement runs, one 30-minute play session, successful save/reload, and practical performance at the agreed settings. Document remaining graphical/audio issues explicitly.

## 14. M5 — Windows multiplayer and simulation correctness

Match the exact game version and content/mod configuration with Windows players. Start with an ordinary unmodified private match; disable optional mods for the baseline. A successful lobby or Steam API initialization does not prove simulation compatibility.

Required manual cases, with logs and participant observations:

1. Sign in, reach services, join a private lobby, and start a two-player match with a Windows peer.
2. Play to normal match completion, including combat and significant simulation activity; record result and any desync/error.
3. Repeat three completed sessions; include at least one 30-minute session or a longer normal match.
4. Host once from the Mac and once from Windows if the game supports the relevant lobby paths.
5. Verify invites/chat, normal logout/exit, and a subsequent login/match.
6. Test disconnect/rejoin only if the current game mode supports it; report unsupported separately.
7. If a failure appears, reproduce against matching versions, then inspect networking, timer behavior, synchronization, and floating-point translation. Keep game version, scenario, and runtime pins fixed during diagnosis.

Use the M1 floating-point/atomic tests and a trusted Windows result to investigate simulation divergence. Do not infer the source of a desync merely from an FEX warning or presume it is only networking. Preserve any game replay/diagnostic artifacts outside tracked source and index them in the result report.

**M5 exit:** three completed Windows-peer sessions with no observed desync, normal lifecycle, and no Rosetta processes. This establishes the tested scenario/build only; avoid claiming universal compatibility.

## 14.1 Cross-cutting gates (R1)

### S1 — signing profile and enforcement

Everything so far runs with SIP disabled, `amfi_get_out_of_my_way=0x1` and an ad-hoc signature carrying `com.apple.developer.cross-architecture-support-unmanaged`. Release xnu kills 4 KiB spawns that fail its private policy (`fourk_fatal_mode`, `LOAD_BADMACHO`). MacNeutron reports running with an Apple-granted `com.apple.developer.cross-architecture-support` capability, a Developer ID, hardened runtime and notarization, with no ad-hoc mode [unverified]. A "robust" result needs a defined signing profile.

1. Record which entitlement names exist, what "unmanaged" means, and whether an individual developer can obtain them (`docs/entitlement-audit.md`).
2. Define the target profile: entitlements, hardened runtime on/off, Developer ID or ad-hoc, which executables are signed.
3. Re-run P0, M0 and the EM-3 experiments under that profile with SIP and AMFI enabled, as soon as an entitlement is available. MAP_JIT region limits under hardened runtime are part of this.
4. Until then, every milestone result is labelled "SIP/AMFI disabled".

This gate does not block local milestones, but no result is called robust without it.

### T1 — regression lanes

- Build Wine with tests enabled. Run selected winetest modules in three lanes: ARM64 native, x86-64 under FEX (WINETEST-X64) and i386 under WoW64 (WINETEST-X86). Record per-module pass/fail and compare lanes.
- Replace count-based pass rules ("32/32", "39/41") in `scripts/test-m0.py` with a registry of required test IDs, so adding a test cannot change what "pass" means silently.
- Add signal, suspend and unwind stress tests to the M0 suite (R1-X18-RACE).
- Re-run all lanes after every Wine/FEX/DXMT rebase. Upstream CI does not build native arm64 macOS.
- Add macOS 27 to the host matrix when available.

## 15. Failure classification and stopping rules

| Symptom | First evidence to inspect | Next experiment |
|---|---|---|
| Host launch killed / signature error | Actual executable signature, embedded entitlement, crash/termination reason | Rebuild/re-sign exact file; run P0-BASE for comparison |
| `Malformed Mach-o file` on 4 KiB spawn | Linker flags, load commands/segment alignment, selected toolchain | Minimal loader using the passing P0 layout; do not blame account access |
| Header/compiler option rejected | Selected source options, actual compiler target, sysroot | Small compile probe; correct host/PE separation |
| Missing emulator import/export | PE import/export inspection and selected Wine ABI | One interface test; update only the incompatible component |
| Crash on framework callback | x18 custom-mode state and guest/native context | A64-CALLBACK/P0-X18-SIGNAL reproducer |
| x64 hello succeeds but a loop hangs | Guest PC, FEX block/exception traces, thread waits | Minimal ALU/atomic/exception case |
| Steam text blank / TLS failure | Fonts/DirectWrite or network/crypto Unixlib bindings | Font/window fixture or NET-TLS, separately |
| Game menu black / wrong textures | Loaded DXMT modules, shader logs, device feature level | D11-CLEAR/TRIANGLE/TEXTURES reproducer |
| Multiplayer divergence | Matched game builds, replay, FP/atomic/timing evidence | Fixed simulation repro and reference outputs |

An unresolved upstream API or architectural gap can genuinely block a milestone. Record the exact dependency, evidence, attempted alternative, and next feasible action. Apple approval is not the default diagnosis on this host. A failed test does not authorize swapping in Rosetta, stubbing successful API results, weakening numerical assertions, or bypassing process semantics.

## 16. Immediate next work package and completion definition

P1's M0 toolchain/source work and native ARM64 console acceptance are implemented
on Wine 11.4. EM-1 (host refuses RWX with EACCES; Wine reported false success,
inconsistent metadata and a leaked reservation) and EM-2 (clean failure, 39/41
extended checks in the `em` profile) are recorded in `docs/executable-memory.md`.

Next work, in order (R1):

1. **Re-port to wine-11.19** (M0.0), fixing R1-X18-RACE, R1-HOTPATH, R1-SPAWN,
   R1-TSO and R1-CPUID on the way. Exit: P0-BASE and all 32 M0 checks pass on the
   new base, with diagnostics on and off, plus the x18 signal stress test.
   If this slips, back-port ed091c479a to the 11.4 profile first.
2. **EM-R1:** non-executable ntoskrnl heap; restore the six drivers.
3. **EM-3 host experiments** (M0-EM), then **EM-4a** (guest-memory policy and
   RW↔RX flip).
4. **Script and source cleanup:** switch `fetch-sources.sh` and `sources.lock.json`
   to upstream Wine/FEX/DXMT pins (3.0); stop `fetch-sources.sh` from deleting
   directories without `.git`; use one work-root default (`$AOE2_WORK_ROOT`, not a
   hard-coded `/Users/...` path); rewrite `build-fex.sh` and `build-dxmt.sh`.
5. **M1:** runtime ABI map (`docs/runtime-abi.md`), Darwin FEX unixlib, registry
   backend selection, M1 tests; then EM-4b (dual-view or MAP_JIT code cache).
6. **M1.5**, then **M1.6** (i386), then M2 onward. G0 and the winemac shim may be
   developed in parallel with M1.
7. Throughout: T1 regression lanes; S1 as soon as an entitlement is available;
   diff each local patch area against MacNeutron and Highball before finalizing it.

The native console checkpoint is achieved; executable heaps, FEX and graphics
remain pending. The whole POC is complete only after M5's Windows-peer sessions,
with repeatable source/build/run instructions and the recorded test evidence.
Until then the README must name the highest verified milestone and the actual
next unresolved task.

## 17. References and their verification limits

- [Wine ARM64 macOS announcement](https://list.winehq.org/hyperkitty/list/wine-devel%40list.winehq.org/message/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/) — explains the host facilities and restricted entitlement names; local probe verifies a subset of behavior.
- Installed SDK `os/arch/arm64.h`, `spawn.h`, `mach/mach_traps.h` — API declarations and strict x18 transition rules. Inspect the SDK actually selected during implementation.
- [Madeira snapshot](https://github.com/willfaust/Madeira/tree/bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120) — superproject cloned and selected documentation/build sources inspected during planning; submodule runtime builds not performed.
- [Wine MR11638](https://gitlab.winehq.org/wine/wine/-/merge_requests/11638) — historical source-audit target; contents/current integration must be verified.
- [DXMT upstream](https://github.com/3Shain/dxmt), [LLVM/MinGW](https://github.com/mstorsjo/llvm-mingw) — primary source candidates; choose exact commits/releases during P1.
- [Route review, 2026-10-06](docs/route-review.md) — sources and confidence levels for every R1 change in this plan.
- [Wine mirror](https://github.com/wine-mirror/wine), tag `wine-11.19`; [FEX](https://github.com/FEX-Emu/FEX); [Hangover](https://github.com/AndreRH/hangover).
- [MacNeutron](https://github.com/chadouming/MacNeutron) at `8813ac1f982f`, [Highball](https://github.com/himbeles/highball-engine-aoe4) at `f27fd69d2e45` — comparison references; their runtime claims are self-reported.
- Apple macOS 27 release notes (developer.apple.com/documentation/macos-release-notes/macos-27-release-notes) — Rosetta timeline.
- [Existing platform test coverage](tests/platform/README.md), [entitlement observations](docs/entitlement-audit.md) — local evidence, including failed alternative layouts and limits of the smoke tests.
