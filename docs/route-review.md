# Route review — 2026-10-06

Review of the plan at main 5b71857, asking whether native ARM64 Wine + ARM64EC/FEX + DXMT is the best route to a Rosetta-free x86 (x86-64 and i386) Wine with GPU on an M4. Produced from six research streams, each adversarially fact-checked. Claims are tagged [V] verified from source/primary doc, [S] secondary report, [I] inference; H/M/L is confidence. Nothing here has been executed on macOS. The plan itself is not changed by this document.

**Legend:** [V] means verified from source or a primary document, by a stream verifier or by me in this pass. [S] means a secondary report. [I] means inference. H, M and L give my confidence. Repo reviewed: origin/main 5b71857 (2026-10-06).

In this pass I checked these myself:
- The MacNeutron, highball-engine-aoe4 and FEX heads, and the FEX tags.
- MacNeutron's README requirements.
- Highball's arm64-line README, `inputs-arm64.json` and `patches-arm64/README.md`.
- The upstream FEX `Source/Windows/Common/FEXUnixLib.cpp` gating.
- Plan lines 178 and 482.

---

## 1. Bottom line

**Yes, this is the right route. Under the user's constraints it is effectively the only one. [H]**

- **Rosetta is going away.** Apple's documentation says Rosetta stays a general-purpose tool through macOS 27. The macOS 27 release notes say "All Intel-based software will no longer be compatible with macOS 28.0, excluding legacy games" (developer.apple.com/documentation/macos-release-notes/macos-27-release-notes) [V-H]. Every Rosetta-bound stack therefore fails the goal: Gcenx builds, Sikarugir, Whisky (unmaintained), the frankea fork, GPTK, and stable CrossOver 26.x on Wine 11.0 [V-H].
- **Upstream Wine already has the Windows-on-ARM emulator interface.**
  - The x86-64 emulator DLL comes from `HKLM\Software\Microsoft\Wow64\amd64` (`dlls/ntdll/loader.c:load_arm64ec_module`).
  - The i386 emulator DLL comes from `Wow64\x86` (`dlls/wow64/syscall.c:get_cpu_dll_name`).
  - FEX's `libarm64ecfex.def` matches the 20 exports in `xtajit64.spec`.
  - All of this is on the PE side and does not depend on the host OS [V-H].
- **Three independent efforts landed on the same design:**
  - **CodeWeavers CrossOver Preview ARM64** (blog post 2026-07-31): native arm64 Wine, a custom macOS FEX, ARM64 DXMT, macOS 26.5+, universal build, no D3DMetal, many launchers broken [S-M].
  - **MacNeutron** (github.com/chadouming/MacNeutron @8813ac1f): upstream wine-11.19 with 20 patches, FEX 4ed80fd with 5 patches, and an ARM64X DXMT. It reports passing D3D11 and D3D12 present tests in both the ARM64EC lane and the x64-under-FEX lane on macOS 27.0.1. Its README requires macOS 27 and an Apple-granted `com.apple.developer.cross-architecture-support` profile; "there is no ad-hoc mode". The runtime results are self-reported [S-M]; I verified the requirements text.
  - **Highball "arm64 line"** (github.com/himbeles/highball-engine-aoe4 @f27fd69, LGPL): upstream wine-11.18 with only 3 patches, Hangover's FEX-2608 DLLs, and a 79-line Darwin FEX unixlib. On an M4 under macOS 27.0 it reports "32-bit and 64-bit x86 programs run within 20 percent of Rosetta on a compute loop". It has no renderer yet [S-M].

**Alternatives:**

| Option | Verdict |
|---|---|
| Box64 | Not a replacement. It has no Darwin host (`src/os` only has `*_linux.c` and `*_wine.c`). Box64EC started 2026-09-21 and has run interpreter-only since 2026-10-05. Its dynarec is RWX and `STRONGMEM` defaults to 0 [V-H]. At most, use `wowbox64` later as an i386 A/B backend. |
| DXVK on MoltenVK | No. MoltenVK 1.4.2 (fae55a1) has no geometryShader, and nullDescriptor and robustBufferAccess2 are false. DXVK 2.0 and later require them [V-H]. |
| DXVK on KosmicKrisp | A credible second path, especially for D3D9. LunarG reports Vulkan 1.4 conformance [S]. DXVK 3.1.1 was tested only on x86_64 and needed a fillModeNonSolid patch. Whether it has geometry shaders is disputed (dappermint's probe says yes; MacNeutron says not until Mesa MR !44786). The arm64 driver is untested. |
| D3DMetal / GPTK | Excluded. It is x86_64-only, licensed for evaluation only, and absent from CrossOver ARM64. CrossOver 26.3's `winemac.drv/d3dmetal.c` is guarded by `#if defined(__x86_64__)` [V/S-H]. |
| CrossOver 27 | Likely the most robust ready-made product when it ships, expected early 2027 (unverified). The preview is not robust yet [S]. |
| Linux arm64 VM + Proton/FEX | A fallback only. It is not Wine on macOS, and its GPU path is weak [I]. |

**Where the real risk is.** The translator or Wine branch choice is not the bottleneck. The risks are:
- the executable-memory design;
- x18 integrity under FEX;
- TSO plumbing;
- the 4K-page / low-4 GiB layout;
- the Apple entitlement.

Only the entitlement is outside the user's control.

---

## 2. Which Wine version to base on

**Base on the wine-11.19 tag: commit `455e3509b98a6919fd4ad1def4803e08c41c03b2` (2026-10-02; tag object d417ce293c9a) [V-H].**
- Pin a tag. Do not track the moving master (eba89375, 72 commits past 11.19).
- Rebase deliberately every 2–4 development releases and re-run P0, M0 and EM each time.
- Upstream CI builds macOS only as x86_64 under `arch -x86_64` (`tools/gitlab/build-mac`), and builds ARM64EC only on Linux. Native arm64 macOS regressions will not be caught upstream [V-H].
- Optionally cherry-pick 1300ec99c7 (autorelease pools for WineMetalSwapChain).

**Why leave 11.4.** cc893ef9cb17 is a genuine upstream tag, but it is 15 development releases and 3,918 commits behind.
- **Latent bug in the plan's exact setup [V-H].** In 11.4, `server/mapping.c:438` rejects view addresses that are not aligned to the *server's* 16K mask. ed091c479a (wine-11.9) fixes this for 4K clients. The M0 patch touches no server file. If the rebase is delayed, back-port this commit immediately.
- **About 103 ARM64/ARM64EC/WoW64 core commits [V-H]**, including:
  - cooperative suspend: b8d8f34ffd, 211e7a3d3b;
  - the KiUserEmulationDispatcher rework: f12bd89a4b, d3b41a854a, 3b6b0cedd9, 56ba8d233c;
  - an EcCodeBitMap bounds check: 2f69c014dc;
  - the fix for bug 60331: 188f1fef35;
  - the dispatcher rework: fc2ba3ffce, 6ddac4544f, 27da578141.
- **Current FEX expects those.** Its CHPEv2 suspend and exception paths rely on them. On 11.4 they degrade rather than fail outright, since Madeira runs FEX-2607 on 11.4 with its own patches [V/I].
- **CodeWeavers' macOS-ARM64 groundwork is upstream after 11.4 [V-H]:**
  - 356547ea6e: SIGBUS handled as SIGSEGV;
  - 321d527d84 and 920240e73e: CPU features and CPU name on macOS;
  - 8ad6011269: macOS address-space limit;
  - fd3fbe3ef3: Wine system thread for the macOS main thread;
  - 1a63b0d7c4: cross-process Metal swapchain via CALayerHost.

**No version removes the local patch [V-H].** Master has no custom-x18, 4K-spawn, layout-emulation, TSO or MAP_JIT code. `configure.ac:991` still links every Darwin build with `-pagezero_size,0x1000`.

**Rejected bases:**
- **wine-11.0 stable:** lacks all of the above.
- **Proton 11:** Linux-only and based on Wine 11.0.
- **Hangover:** Linux-only, Wine 11.16 plus 9 commits. Its WoW64 patches are still useful i386 references: d6a44ddebc, 6789030082, 594cf64e8b, 7b1ccaa862, 07defd3b97.
- **Madeira's fork:** wine-11.4 plus 109 iOS commits.
- **dappermint/winecx:** a third-party reconstruction of CrossOver 26.3.
- **MR !11638:** very likely trcrsired `apple-silicon-mac-woa` 458eb1a481 [S]. It is unentitled and native-ARM64-only. It relies on xnu's "temporary override" that keeps x18 for binaries built with SDK < 13.0 (`osfmk/arm64/machine_task.c`). It uses a process-wide `current_teb` and has no 4K pages and no low 4 GiB. It therefore cannot support identity-mapped WoW64.
- **CrossOver 26.3 tree:** fails to load kernel32 when built for arm64 (c0000045), per Highball [S].

**Best public cross-check:** MacNeutron's 11.19 patch queue. It uses the same design as this plan: entitled, 4K pages, strict x18 toggling, exec via SETEXEC [S; AI-assisted, unreviewed]. Future diff targets are CrossOver 27's LGPL sources and Brendan Shanks' macOS ARM64 MRs. Highball says he announced them on wine-devel on 2026-08-07, which is probably the announcement the plan cites [S-L].

**Local patches: re-port by hand.**
- Both M0 and EM fail on 11.19 with 7 rejected hunks each [V]. The rejects are in:
  - `configure` and `configure.ac`, because the preloader context changed in dee9173b15, c2aaafcf10 and f82008b27b;
  - four places in `signal_arm64.c`: `call_user_mode_callback`, `ill_handler`/`bus_handler`, `signal_init_process`, `__wine_unix_call_dispatcher`;
  - `virtual.c`.
- Hunks that do apply in the dispatcher land in code whose meaning changed: new `_kernel_stack`/`_user_stack` labels, a second `syscall_dispatcher_return_slowpath`, and a `usr1_handler` PC rewrite.
- Only the SIGBUS hunk is superseded. The plan has no CPU-feature or address-limit hunk to drop [V].
- Re-check the low reservation against 60c5ce0263 and 4c18d96e9b.
- Rebase **before** doing more EM work in `virtual.c`.

**Companion pins:**
- **FEX:** Do **not** use FEX-2609.1 (9fbdc00b). It is an off-main point release and lacks af0494046 (WOW64 CHPEv2 suspend/exception, merged via f18599d09) [V]. Pin main at or after f18599d09 (e.g. 7d3090f78237), or FEX-2610 once it is tagged.
- **Emulator selection:** select through the `Wow64\amd64` and `Wow64\x86` registry values. The value must be a short bare DLL name resolved from system32 [V].
- **DXMT:** use upstream 3Shain/dxmt main e94c312 or later. v0.80 lacks `-marm64x` (3b78076) and hybrid_patchable (20af9fc) [V-H].

---

## 3. Madeira: reference, never base [H]

Madeira is an iOS single-process runtime: the wineserver is a thread, Windows processes are pseudo-processes, and JIT comes from an attached debugger. Its real runtime is about 115k lines of iOS replacement C under `build/` (`virtual_ios.c` alone is 26,641 lines). Each heavy mechanism works around an iOS limit that macOS 26.5+ removes:

| iOS limit | Madeira workaround |
|---|---|
| Hard 4 GB `__PAGEZERO` | Offset-window WoW64 |
| x18 zeroed on context switch | TEB in a TSD slot, plus `[x18]` access emulation |
| No executable memory outside one debugger pool | PE copy into the pool, PC redirection, store emulation |
| No hardware TSO | Software TSO |

Its DLLs are ABI-incompatible with an x18-based macOS Wine [V-H].

**Harvest:**
- **FEX DualMap write path**, as a checklist of every place FEX writes code (willfaust/FEX ios-port-2607): `DualMap.h`, `Buffer.h` WritePtr, the `JIT.cpp` link and backpatch writes, `Dispatcher.cpp`, `ArchHelpers/Arm64.cpp`.
  - The verifier found about 80+ write sites, not 46.
  - Per `LICENSE-MADEIRA.md`, changes published before 2026-08-28 remain MIT; later ones are GPL-3+.
  - Prefer MacNeutron's macOS port (fex/0005) or a clean re-implementation.
  - Lesson: invalidate the **RX** virtual address after writing through the RW alias. The "kernel IPI" explanation in 6084de076 is contradicted by Madeira's own `__clear_cache`-based flush [V].
- **CPU features:** the sysctl feature list (`WineProcessBridge.m`) and the AFP-off / LRCPC2-on tuning.
- **Bug reports to reproduce:** the `free_async_queue` use-after-free (d0c56b04eb; upstream `server/async.c` is unchanged, but it is probably rare with separate processes) and the RtlIsEcCode bounds check (ac650deca3).
- **Tests:** `asmconf-x64`, FEX's 2,239 golden instruction tests re-hosted as a PE, as an M1 acceptance test. It is GPL-3; rebuild from source.
- **Steam notes:** SteamSetup and the bootstrap `steam.exe` are 32-bit; the CEF flags it uses; the Windows 8 version-lie trap that picks the legacy channel.

**Avoid:**
- the `build/*-unix` replacement runtime;
- execution from the pool and its aliases;
- x18 avoidance;
- guest windows;
- software-only TSO;
- the prebuilt `xtajit*.dll`;
- the ARM64EC loader-ordering patches 06143656ec, 948212bd97, f3339da9f6 and a052a7f8e3 (verifier correction: the CRT link is the cause for some, not all);
- the DXMT fork. It defines `DXMT_IOS` for every Windows target, installs to a non-standard `arm64ec-windows` directory and adds GPL-3 code.

**Instead of the loader-ordering patches:** they exist because Madeira links FEX against the mingw CRT after ld.lld crashed on llvm-mingw 20260421. Use a newer llvm-mingw (20260908 or 20260922) or Hangover's prebuilt MIT DLLs instead.

---

## 4. The RWX/JIT blocker: the right design

**Facts:**
- **Plain RWX is permanently impossible [V-H].** xnu fails any writable-and-executable mapping not created with MAP_JIT on every non-alien macOS process (`xnu-12377.121.6 osfmk/vm/vm_map.c` ~3180/5772, `VM_MAP_POLICY_WX_FAIL`). No entitlement changes this. EM-1's EACCES is permanent, so "native RWX at the same address via mprotect" should be dropped as a goal.
- **MAP_JIT|MAP_FIXED works in 4K processes since macOS 26.4 [V-H].** It is allowed for arm64 4K, non-"exotic" maps since xnu-12377.101.15 (26.4). The cross-arch entitlements grant MAP_JIT (`tests/map_jit_x86_64_compat.c`).
  - `docs/executable-memory.md` is outdated rather than wrong: the GitHub xnu `main` branch it links is frozen at xnu-12377.1.9 (macOS 26.0). Cite release tags instead.
  - `vm_map_is_exotic()` is closed source, so this must be tested in a real layout-emulated 4K child.
- **MAP_JIT has caveats [S]:**
  - Write permission is per thread.
  - Highball reports that a toggle made inside a signal handler is lost on return.
  - MacNeutron reports that mprotect fails on a MAP_JIT range once it is RWX (unentitled, 16K pages).
  - Under hardened runtime, Apple documents a single MAP_JIT region, while xnu allows multiple unless `single_jit`. Test under the target signing profile.
- **FEX itself allocates PAGE_EXECUTE_READWRITE [V-H].** This covers its code buffers, dispatcher and trampolines (`AllocatorHooks.h:56-61`, with EC_CODE on ARM64EC and plain on WoW64; `SharedCodeBufferManager.cpp:21`; `ARM64EC/Module.cpp:695`; `WOW64/Module.cpp:550`). The blocker is therefore on M1's critical path. EM-2's fail-with-ACCESS_DENIED policy breaks FEX's initialisation and its InvalidationTracker, which toggles PAGE_EXECUTE_READ and PAGE_EXECUTE_READWRITE.

**Design, split by who actually needs host execute:**

1. **x86 guest memory in emulated processes** (non-EC_CODE memory in ARM64EC processes; guest memory under WoW64):
   - Accept every PAGE_EXECUTE_* request and keep the Windows protection in Wine's metadata.
   - On the host, drop **only** PROT_EXEC and keep read/write exact, or FEX's self-modifying-code write traps stop firing.
   - Never fail the request.
2. **FEX's code cache:**
   - **ARM64EC:** Wine backs EC_CODE allocations with a dual view: one section mapped RW and RX at a constant offset (MacNeutron Wine 0011 plus FEX 0005). The alternative is one large MAP_JIT region that FEX toggles per thread through its unixlib.
   - **WoW64:** there is no EC bitmap. It needs a small FEX patch that requests the pool explicitly, or an address rule (FEX allocates top-down; guest memory is below 4 GiB; Hangover's d6a44ddebc keeps WoW64 host allocations above 4 GiB).
3. **Native ARM64 RWX:**
   - Unblock the six drivers now: make `ntoskrnl_heap` non-executable on aarch64 macOS. trcrsired uses `HeapCreate(0,0,0)` in 458eb1a481; dappermint 88ca5b254b falls back to a plain heap [V].
   - For other native RWX, use a fault-driven RW↔RX flip (Highball 0019, citi94 4a50ce17c8, MacNeutron 0006). Document its known livelock when code stores into the page it is executing [S].

**Bring-up order.** The flip patch alone let Highball run unmodified Hangover FEX [S], so it is the cheapest way to unblock M1. The dual view or MAP_JIT is the performance and robustness target.

**EM-3 experiments**, on 26.6.2 and on 27, under the eventual signing profile:
- MAP_FIXED|MAP_JIT at Wine-chosen low addresses in an entitled, layout-emulated 4K child;
- a dual-view section;
- flip throughput;
- cross-core instruction-cache publication.

---

## 5. Plan review

**Sound:**
- **Architecture:** separate Mach tasks, 4K clients beside a 16K wineserver (upstream now supports this explicitly via ed091c479a), ARM64EC plus FEX, FEX WoW64, DXMT.
- **x18:** explicit custom-x18 toggling rather than relying on the SDK < 13 override.
- **Low memory:** identity low-4 GiB via layout emulation. The entitlement gives a "soft" PAGEZERO (`mach_loader.c`), which is exactly what makes identity WoW64 possible [V].
- **Process:** evidence discipline, and the EM-1/EM-2 diagnosis.
- **Already right in the docs:**
  - `docs/executable-memory.md` already says translated bytes need no host exec.
  - Plan line 482 already marks MR11638 as "historical". The criticism of MR11638 in the task text is overstated.

**Wrong or stale:**
1. The P1.2 upstream audit was never done. "Wine 11.18 remains a candidate" (plan:178) is stale, and the base came from Madeira's fork history.
2. EM-4's exit criterion ("all existing positive executable probes") plus the §16 ordering gate M1 on an unachievable native-RWX goal.
3. The MAP_JIT|MAP_FIXED statement in `docs/executable-memory.md` (see §4).
4. **M0 signal race (verified by code reading).** A signal that lands after `MACOS_ENTER_GUEST` but before the switch to the user stack is classed as inside a syscall, so custom mode is not restored. The toggle is strict: `libsyscall/os/x18.c` traps if called with the current state. When the mode is off, the kernel zeroes x18 on exception return. The next leave-guest call then traps, or the TEB in x18 is lost. Upstream fc2ba3ffce changes exactly this window, so fix it during the re-port.
5. **Hot-path overhead.** `getenv` runs on every transition when `AOE2_M0_DIAGNOSTICS` is unset, `sysconf` runs on every transition, and `getenv` runs in `system_time_precise`. `test-m0.py` always sets the variable, so the release path is untested. The x18 toggle itself is cheap (a commpage TPIDR_EL0 update; about 1.5 ns per MacNeutron) [V/S].
6. **4K re-spawn.** It leaves a waiting 16K parent per Windows process, forwards no signals and reports `128+N` exit codes. Instead, use `posix_spawn(POSIX_SPAWN_SETEXEC)` with `posix_spawnattr_set_4k_page_size_np` in ntdll's exec path; Wine already uses SETEXEC in `dlls/ntdll/unix/loader.c`. Check the entitlement first, because an unentitled 4K exec is a silent SIGKILL.
7. **TSO.** The patch calls `thread_set_x86_64_compat(1)` on every thread, including pure ARM64, but FEX is never told hardware TSO is on, so it still emits software barriers.
   - Ship a Darwin FEX unixlib; Highball's `fex/fexunixlib_darwin.cpp` exists.
   - Conflict: upstream FEX gates its unixlib calls on `Available()` (I checked `Common/FEXUnixLib.cpp`), so the helper should be optional. Highball, however, reports SIGKILLs from raw Linux syscalls without a Darwin helper when using Hangover's DLLs. Treat the helper as required from day one.
8. **CPU features.** `get_core_id_regs_arm64` is a stub outside Linux (`system.c:2045-2111`). FEX then reads zero ID registers and runs at an ARMv8.0 baseline without LSE. Synthesize the values from `hw.optional.arm.FEAT_*` [V-H].
9. **Scripts:**
   - `build-fex.sh` has no MinGW toolchain file, so it would configure FEX for the macOS host. It does not build `wow64fex`, and it targets Madeira's fork.
   - `build-dxmt.sh` also targets Madeira's fork.
   - `fetch-sources.sh` runs `rm -rf` on directories without `.git`.
   - Work-root defaults mix `/Users/szotyesz` and `$HOME`.
   - The Wine base is fetched from the willfaust URL.
   - `verify-no-rosetta.sh` and `runtime-abi.md` are listed in the plan but do not exist.
10. **Docs drift:** "34/41" vs "39/41"; "planned, not implemented" above items that are done; a 33/35 count that double-counts; `sources.lock.json` cites §16 instead of §3.1.

**Missing for the general goal:**
- **32-bit.** There is no standalone milestone. It needs:
  - `--enable-archs=arm64ec,aarch64,i386`;
  - a `wow64fex` build;
  - a FEX WoW64 JIT allocator;
  - a test that [64 KiB, 4 GiB) is reservable for large-address-aware programs. Highball reports that the `0x170000000` layout works, whereas the plan recorded a local failure; retest.
  - the Hangover WoW64 patches as references;
  - the DXMT i386 build, with a test of 4096-aligned `newBufferWithBytesNoCopy` below 4 GiB;
  - 32-bit SEH and suspend tests.

  The only public data point for i386 under FEX on macOS is Highball's compute loop [S].
- **GPU.** A winemac `macdrv_functions` shim is mandatory. DXMT expects that export or the hidden symbols, plus the Wine 8 `macdrv_win_data` layout; otherwise it aborts at `d3d11_swapchain.cpp:138` [V-H].
  - Shim sources: CrossOver's `d3dmetal.c` (x86_64-guarded), MacNeutron 0013, and dappermint 713015f, 13e6a88 and 565f638.
  - Long term: DXMT PR #166 plus Wine MR 11058 (ExtEscape; unverified).
  - Add a G0 Metal probe in the 4K/x18/layout child.
  - Apply DXMT per application, because Steam CEF/ANGLE has open bugs (DXMT #141, #183).
  - Cover cross-process CEF swapchains, D2D/IDXGISurface interop (PR #222 is still open), and a D3D9 order: wined3d, then mtld3d (zlib licence), then DXVK on KosmicKrisp.
- **Synchronization performance.** Upstream's in-process sync is ntsync, which is Linux-only, so every wait on macOS is a wineserver round trip. MacNeutron carries CrossOver's msync.
- **Testing.**
  - Build with tests enabled and run winetest subsets in three lanes: ARM64, x64 under FEX, and i386 under WoW64.
  - Replace the count-based pass rule with a registry of required test IDs.
  - Add signal, suspend and unwind stress tests.
  - Run FEX with `X87ReducedPrecision=0` for lockstep multiplayer.
- **Entitlement and SIP.**
  - The POC runs with SIP off, `amfi_get_out_of_my_way=0x1`, and an ad-hoc signature carrying `-unmanaged`.
  - Release xnu kills 4K spawns that fail the private policy (`fourk_fatal_mode`, `LOAD_BADMACHO`) [V].
  - MacNeutron reports a third-party Developer ID with the managed capability, hardened runtime and notarization [S].
  - This is the gating risk for "robust".
- **Test matrix:** add macOS 27. Both MacNeutron and Highball measured on it.
- **Strategy and risks.** Upstream FEX has no macOS plans (discussion #3267) and bans AI-generated contributions, so the macOS FEX patches stay downstream permanently.

**Prioritized changes:**
1. Re-port M0 and EM onto wine-11.19 now. Fix the signal race and the hot-path diagnostics in the process, and move the 4K spawn into the SETEXEC path. If the rebase slips, back-port ed091c479a immediately.
2. Fix the six drivers with a non-executable `ntoskrnl_heap`.
3. Re-scope EM-3 and EM-4 around the consumer split in §4. Use the fault-flip for bring-up, and remove positive native-RWX probes from the M1 gate. Do not carry EM-2's fail-RWX behaviour into M1.
4. Switch the pins: upstream FEX main at or after f18599d09, and DXMT e94c312 or later. Rewrite `build-fex.sh` with `toolchain_mingw.cmake` and `MINGW_TRIPLE=arm64ec-w64-mingw32` / `aarch64-w64-mingw32`. Select backends through the registry.
5. Write a Darwin FEX unixlib and a Darwin `get_core_id_regs_arm64`. Enable TSO only in emulated processes.
6. Add the winemac `macdrv_functions` shim and the G0 Metal probe.
7. Add a standalone i386/WoW64 milestone.
8. Define the target signing profile and re-run P0, EM and M0 with SIP and AMFI enabled.
9. Add the winetest lanes and the required-test-ID registry.
10. Diff the local patches against MacNeutron and Highball. Archive the wine-devel announcement and MR11638 from a host that can reach winehq.org.
11. Clean up the scripts and docs.

---

## 6. Open questions / unverified

- **Unreachable from this container:** MR !11638's contents and status, and the wine-devel announcement (message CKG5CEN2…). gitlab.winehq.org and list.winehq.org were blocked.
- **CrossOver 27:** when its ARM64 LGPL Wine sources will be published, how it handles executable memory, x18 and TSO, and whether its custom FEX will ever be published (FEX is MIT, so publication is not required).
- **On 26.6.2, in an entitled, layout-emulated 4K child:**
  - Does MAP_FIXED|MAP_JIT succeed, or does `vm_map_is_exotic()` return true?
  - Do dual-view sections work?
  - What MAP_JIT region limits apply under hardened runtime?
- **Darwin unixlib conflict:** is the helper strictly required for bring-up? Upstream source says optional; Highball reports a SIGKILL without it.
- **Entitlement access:** can an individual obtain `cross-architecture-support` or `-unmanaged`, and what does "unmanaged" mean? There is no Apple documentation; my only source is MacNeutron's report.
- **`thread_set_x86_64_compat`:** what it does beyond TSO. Its implementation is private.
- **KosmicKrisp:** geometry-shader status, and VK_EXT_map_memory_placed / external_memory_host support on the arm64 driver.
- **AoE2DE under DXMT:** no reports exist. Unknowns are D2D text rendering, and whether Windows Steam fetches the Windows depot now that a native Mac AoE2DE exists without crossplay (since 2026-05-28 [S]).
- **Steam on a native-ARM64 macOS Wine:** not working reliably anywhere public [S].
- **Whether wine-11.0.x maintenance releases exist:** unknown. The question is moot either way, since 11.0 lacks the 11.x ARM64EC work.