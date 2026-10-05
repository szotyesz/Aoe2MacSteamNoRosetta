# AoE2DE on Apple Silicon Without Rosetta — Local POC

Updated: 2026-10-05. This plan describes work still to implement unless explicitly marked verified.

## Goal and working environment

Demonstrate the Windows Steam build of Age of Empires II: Definitive Edition on this Apple Silicon Mac, without Rosetta, using native ARM64 Wine, FEX CPU translation, and DXMT Metal rendering. The final POC target is playable gameplay and a completed multiplayer match with Windows players on matching game versions.

Work proceeds on the user's temporary macOS installation with SIP and AMFI disabled. Entitlement access was attempted on another OS installation and did not work; the user is querying Apple in parallel. Apple's response is not a prerequisite for this local experiment. This POC makes no claim about operation with security enforcement enabled or Apple account authorization.

## Architecture

```text
Windows Steam / AoE2DE (x86-64, i386 helpers where required)
    -> native ARM64 Wine / ARM64EC / WoW64
        -> FEX: x86/x86-64 CPU code to ARM64
        -> DXMT: D3D11 to Metal to Apple GPU
```

Use free/open-source compatibility components. Keep host executables native ARM64 and translate Windows code only. The main engineering risk is Darwin FEX integration with Wine, including mixed Steam helper processes and ARM64EC/native ABI boundaries.

## P0 — Platform capability probe

Run `scripts/test-platform.sh` before porting. It compiles a native ARM64 test using the selected SDK, applies a local ad-hoc signature containing `com.apple.developer.cross-architecture-support-unmanaged`, and launches isolated children with `posix_spawnattr_set_4k_page_size_np()`.

Required checks:

- 4 KiB process pages: both `sysconf` and Mach report 4096; individual 4 KiB page protection succeeds.
- Address layout: link with `-Wl,-x86_64_layout_emulation`, reserve a 4 GiB PAGEZERO, remap and access memory at Windows USER_SHARED_DATA address `0x7ffe0000`.
- Custom x18 ABI: enter custom mode, write/read x18 in assembly, exit before returning to macOS calls. Mask signals around this section.
- TSO: enable and disable `thread_set_x86_64_compat()` on the main thread and explicitly on a fresh pthread; do not assume inheritance.

**Verified locally on 2026-10-05:** all checks pass on macOS 26.6.2 (25G83), SDK 27.0, SIP disabled, boot argument `amfi_get_out_of_my_way=0x1`. The probe is targeted at 26.5 but has not been run on 26.5 itself. See `tests/platform/README.md` for coverage and limits.

This is a runtime gate, not an entitlement-approval gate. If a capability fails, preserve its error/exit/signal and investigate the current kernel, SDK, linker, signature, and process layout.

## P1 — Toolchains and source audit

- Record the selected developer directory, compiler, linker, SDK, and native build-tool architectures. Command Line Tools are sufficient for the current platform probe; determine additional requirements from actual builds.
- Select an ARM64-hosted LLVM/MinGW toolchain with ARM64EC PE support; compile native ARM64 and ARM64EC Windows probes.
- Audit Wine's current ARM64 macOS changes and MR11638. Wine 11.18 is only a proposed baseline until its tag and required fixes are verified.
- Audit FEX upstream and the experimental Darwin fork, plus DXMT's ARM64EC and native Metal components.
- Pin exact revisions in a source manifest. Classify each necessary change as upstream, a focused local patch, superseded, or a temporary workaround.

**Status: pending.** Source revisions, toolchain choices, and the patch matrix have not been verified. Produce exact source pins, a native toolchain report, and concrete Darwin/ABI porting gaps before implementing Wine changes.

## M0 — Native ARM64 Wine

Adopt or implement address-layout handling, 4 KiB child-process creation, x18 ABI transitions at Windows/macOS boundaries, and explicit per-thread TSO initialization. Use local ad-hoc signing as demonstrated by P0. Add a minimal loader bundle only if the actual runtime requires one.

Start by verifying the configuration `--enable-archs=aarch64,arm64ec` against the pinned Wine source; it is not a promise that stock Wine builds or runs on this platform.

**Status: pending.** No working Wine build or Windows console probe is present. The unvalidated build script and malformed patch drafts have been removed. Apple entitlement approval does not block this local milestone.

**Acceptance:** an ARM64 Windows console probe runs; low mappings/page size are verified; Windows API calls, native callbacks, thread startup, and exception handling pass focused probes. All host processes are ARM64.

## M1 — x86-64 execution through FEX

Audit and adapt FEX memory/JIT management, exception handling, TLS, synchronization, and Darwin unixlib integration. Verify the emulation DLL naming/installation and Wine's `xtajit64.dll` interface against the source pins.

**Acceptance:** a source-controlled x86-64 Windows console probe executes through FEX with correct output and status across repeated launches. Exercise threads, exceptions, memory-protection changes, and host callbacks. Verify the PE architecture and collect evidence that FEX executes it. Keep Steam and graphics outside this milestone.

## M1.5 — Local runtime integration

Validate the complete M1 runtime from a clean Wine prefix, including child launches, fresh-thread compatibility setup, executable signatures, and repeatable build/run commands on this installation.

**Acceptance:** repeatable x86-64 execution with documented host configuration and no translated Mach-O processes in the runtime tree. Apple account entitlement approval is not part of this gate.

## M2 — Mixed architectures and Windows Steam

Determine the architectures needed by the selected Steam build. Add i386/WoW64 support where required and run a small 32-bit Windows probe first.

**Acceptance:** Steam installs, updates, logs in, persists the session, displays Library/Store, downloads, restarts helper processes, and launches a test application without Rosetta.

## M3 — D3D11 and AoE2DE menu

Build DXMT's required PE/native components and verify ARM64EC/native ABI transitions. Run a small D3D11 device-creation/rendering test before installing and launching AoE2DE.

**Acceptance:** confirmed Metal-backed rendering and a stable AoE2DE main menu.

## M4 — Gameplay and performance

Validate rendering, windowing/fullscreen, input, audio, save/load, frame pacing, and extended-session stability in a representative single-player scenario. Record Mac model, resolution, settings, scenario, and CPU/GPU timing before judging performance.

**Acceptance:** practical gameplay on this Mac, with measured performance and known limitations recorded.

## M5 — Windows multiplayer

Validate Steam/AoE services, lobbies, game-version compatibility, simulation synchronization, and session stability.

**Acceptance:** join Windows players and complete a real match; repeat successfully and record any desyncs or failures.

## Repository and execution order

Store test sources and build instructions in `tests/`, scripts in `scripts/`, focused patches in `patches/`, and source/milestone observations in `docs/`. Keep downloaded source trees, build outputs, prefixes, and machine-specific signing material outside tracked source. The platform probe builds in a temporary directory and removes its outputs.

```text
platform capability probe -> toolchain/source audit -> ARM64 Wine
    -> FEX / x86-64 probe -> local runtime integration
    -> mixed-architecture Steam -> D3D11 / game menu
    -> gameplay measurements -> Windows multiplayer
```

The POC is complete when this installation repeatedly launches Windows Steam and AoE2DE without Rosetta, renders through Metal, supports practical gameplay, and completes multiplayer sessions with Windows players.

## References

- [Wine ARM64 macOS announcement, August 7, 2026](https://list.winehq.org/hyperkitty/list/wine-devel%40list.winehq.org/message/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/) — describes the required facilities and entitlement names; inspected for this probe.
- Installed SDK headers: `os/arch/arm64.h`, `spawn.h`, and `mach/mach_traps.h` — actual declarations and custom x18 contract used by the test. SDK 27.0 annotates x18 as 26.4 and 4 KiB spawning as 26.0; the announcement describes their usable combination in 26.5. Address-layout support is described as 26.4. Treat 26.5 as the full POC baseline rather than the introduction version of every API.
- [Wine MR11638](https://gitlab.winehq.org/wine/wine/-/merge_requests/11638) — source audit pending.
- [Experimental FEX Darwin fork](https://github.com/Jpkovas/FEX_MacOs) — reference candidate; suitability unverified.
