# Executable-memory investigation

The next task after console M0 is a real executable-memory contract, required
before restoring the six excluded drivers or integrating FEX. This change adds
three source-controlled Windows ARM64 probes and repairs timeout reporting when
Darwin Wine spawn wrappers leave descendants outside the launcher's process group.
Timeout cleanup identifies children by the exact loader path and this run's
isolated prefix; unrelated Wine prefixes are not selected.

Reproduce with `./scripts/test-platform.sh` and
`./scripts/test-m0.py --exec-memory`. The extended runner now requires all 41
checks to pass (the 35 below plus six EM-1 state cases) and exits nonzero if any
fails. The original 32-check mode is preserved. The host-side matrix is
`./scripts/test-host-vm.sh`.

## Initial observed results (35-check run)

On macOS 26.6.2 (25G83), SDK 27.0, with the existing signed ARM64 console runtime:

| Test | Observed result |
|---|---|
| P0 baseline | PASS; memory, x18 and TSO cases |
| A64-EXEC-HEAP | FAIL; `HeapCreate(HEAP_CREATE_ENABLE_EXECUTE, 0, 0)` returns null, Windows error 8 |
| A64-EXEC-RWX | FAIL; allocation returns a pointer, but calling code at `0x60000000` raises an execute access violation and exits 5 |
| A64-EXEC-TRANSITION | PASS; RW → RX → RW → RX transitions and cache flushes produce exactly 42 then 43 |

The final run is `$AOE2_WORK_ROOT/runs/m0-20261006T134228626008Z`:
**33/35 checks pass**, including all 32 console baseline checks and both server
cleanup checks; the extended runner exits 1 as required. No case times out.
[Raw results](evidence/executable-memory/results.json), executable probe logs,
PE header inspection and cleanup logs are preserved under
`docs/evidence/executable-memory/`. Python syntax and `git diff --check` pass.
The tracked changes are `tests/m0/runtime.c`, `scripts/test-m0.py`, their test
README, this evidence report, the top-level README, milestones and plan.

No runtime patch, extra entitlement or driver restoration is included in this
task. These results establish that explicit executable protection transitions
work here; they do not establish support for simultaneous writable/executable
Windows pages or for FEX's JIT allocator.

## Source evidence

The inspected source is the existing Wine 11.4 base
`cc893ef9cb17b994bfd1f1a1f7355be55e615623` plus the tracked M0 patch.
In `dlls/ntdll/unix/virtual.c`, `map_view` first removes `PROT_EXEC` from the
anonymous mapping's host permissions. `allocate_virtual_memory` then calls
`mprotect_range` for executable reservations but ignores its return value.
The separate commit path calls `set_protection`, which returns
`STATUS_ACCESS_DENIED` when `set_vprot` cannot apply host permissions.
In `dlls/ntdll/heap.c`, executable heaps choose `PAGE_EXECUTE_READWRITE` and use
separate reserve and commit calls. This explains the different API failure paths;
the exact host errno and a working writable/executable mapping design remain
unverified.

## EM-1 host result: RWX is refused with EACCES

`./scripts/test-host-vm.sh` builds `tests/exec-memory/host-vm-probe.c` with the
P0 layout flags and ad-hoc signature (unmanaged cross-architecture entitlement),
then runs each case in an isolated child with a 30-second deadline, in both a
4 KiB-page child and a default 16 KiB-page child. It exits nonzero if a required
RW↔RX/RO transition is refused, generated code returns a wrong value, the RO
write does not fault, or a child times out. Requests for simultaneous write and
execute permission are recorded as observations. Result on 2026-10-06, macOS
26.6.2 (25G83), SDK 27.0: **12/12 cases pass**
([log](evidence/executable-memory/host-vm-probe.log)).

| Operation | 4 KiB child | 16 KiB child | With TSO enabled |
|---|---|---|---|
| `mmap(PROT_READ\|WRITE\|EXEC, MAP_ANON)` | EACCES | EACCES | EACCES |
| `mprotect` RW→RWX, RX→RWX | EACCES | EACCES | EACCES |
| `mprotect` RW→RX, execute, RX→RW, rewrite, RX, execute | pass | pass | pass |
| Independent RX on an interior 4 KiB page, neighbour stays RW | pass | n/a | pass |
| Write after RW→RO | SIGBUS (expected) | SIGBUS (expected) | — |

`mach_vm_region` reports maximum protection 7 (rwx) for these regions, so the
refusal is not a maximum-protection limit: the kernel rejects a simultaneously
writable and executable current protection for ordinary anonymous memory, for
both page sizes, with this signature, under the current SIP/AMFI configuration.
TSO does not change it. Earlier ad-hoc logs that suggested a write fault after an
RX→RW cycle were not reproduced: every post-cycle write succeeds.

This explains both Windows-side failures with no further assumption about Wine's
caller: `allocate_virtual_memory` ignores the EACCES from `mprotect_range`,
returning a pointer whose host protection is RW (A64-EXEC-RWX then faults on
execute), while the commit path through `set_protection` maps the same failure
to `STATUS_ACCESS_DENIED` (HeapCreate: Windows error 8). Confirming the errno
inside Wine itself remains part of the opt-in diagnostics below.

## EM-1 Windows state result: 34/41, four inconsistencies and a leak

`tests/m0/runtime.c` adds six cases. Each accepts success or failure of the
executable request, but Windows-visible state (`VirtualQuery`) must match real
writes and executions, which are probed under `__try` so a fault fails the case
instead of the process. Run `$AOE2_WORK_ROOT/runs/m0-20261006T162215642959Z`:
**34/41** — all 32 console checks, A64-EXEC-TRANSITION and A64-EXEC-PROTECT-SPAN
pass; the runner exits 1 as required. No case times out.
[Results and per-case logs](evidence/executable-memory/em1-state/) (native
`M0-THREAD/NATIVE/VM` diagnostic lines filtered from stderr; full logs remain in
the run directory).

| Case | Observed | Defect shown |
|---|---|---|
| A64-EXEC-COMMIT | `NtAllocateVirtualMemory(MEM_COMMIT, PAGE_EXECUTE_READWRITE)` in a reservation returns `0xc0000022`, yet `VirtualQuery` reports the page `MEM_COMMIT`/`PAGE_EXECUTE_READWRITE` | `set_vprot` writes metadata before `mprotect_range` fails |
| A64-EXEC-PROTECT | `VirtualProtect` RW→RWX fails with error 5, yet the page is reported `PAGE_EXECUTE_READWRITE` | Same metadata-before-host ordering |
| A64-EXEC-ROLLBACK | Write-watched RW pair, page 2 already written: RW→RWX fails with error 5 and both pages report RWX | Partial host change (page 1 RX succeeds, page 2 RWX refused) plus metadata; no injection needed |
| A64-EXEC-ALLOC-STATE | Fixed reserve+commit RWX at `0x61000000` succeeds and reports RWX; executing faults | Ignored `mprotect_range` result in `allocate_virtual_memory` |
| A64-EXEC-HEAP-LEAK | 0/32 executable `HeapCreate` succeed; private allocations 8→40, bytes `0x52b000`→`0x72b000` (+32 × 64 KiB) | Confirmed: `allocate_region` keeps its reservation after a failed commit |
| A64-EXEC-PROTECT-SPAN | Committed+reserved span is refused (error 487) and both pages keep their state | Control passes; not a regression target |

EM-1 exit is met for state, leak and host errno. The errno is established by
the standalone host probe and by source reading; the opt-in in-Wine diagnostic
below is still worth adding with the EM-2 patch so a future failure names its
host call directly.

### Existing Wine write-exception mechanism (input to EM-3/EM-4)

The pinned source already has an emulator-facing W^X-compatible mode.
`NtSetInformationProcess(ProcessManageWritesToExecutableMemory)` calls
`virtual_enable_write_exceptions` (`dlls/ntdll/unix/process.c`); afterwards
`set_vprot` and `set_page_vprot_exec_write_protect` add `VPROT_WRITEWATCH` to
pages that are both executable and writable, so `get_unix_prot` yields host RX.
A write then faults; `virtual_handle_fault` raises `STATUS_IN_PAGE_ERROR` with
`ExceptionInformation[2] = STATUS_EXECUTABLE_MEMORY_WRITE` unless the thread set
`ThreadAllowWrites` (`dlls/ntdll/unix/thread.c`). `NtSetInformationVirtualMemory
(VmPageDirtyStateInformation)` re-arms protection. This is the hook an x86
emulator uses for self-modifying-code invalidation: translated x86 bytes never
need host execute permission, so FEX-managed guest code pages do not by
themselves require host RWX. It does not give native ARM64 code (e.g.
`ntoskrnl_heap` users) a same-address writable/executable page. EM-3 must
evaluate it alongside the candidates below rather than inventing a parallel
write-tracking mechanism.

## EM-2 result: failures are clean, 39/41 on the candidate profile

The candidate is `patches/wine-em/0001-native-arm64-macos-exec-memory.patch`
(sha256 `424eb2d9…12be`), a single combined diff = unchanged M0 patch + EM-2.
It is built in separate trees (`AOE2_WINE_PROFILE=em`, `sources/wine-em`,
`build/wine-em`); `git apply --check` passes against a clean export of the base.
Changes and their rationale are in [the patch README](../patches/wine-em/README.md):
transactional `set_vprot` (per-page metadata saved, restored and reapplied to
the host on failure), checked placeholder replacement, deletion of a new view
whose executable host protection is refused, opt-in `WARN` of the failing host
call, and release of `allocate_region`'s reservation after a failed commit.

Run `$AOE2_WORK_ROOT/runs/em-20261006T163904285452Z`
([evidence](evidence/executable-memory/em2-candidate/)): **39/41**. All 32 console
checks, both server-cleanup checks, A64-EXEC-TRANSITION and all six EM-1 state
cases pass; executable heaps now leave private allocations at 7→7. The two
remaining failures are the positive requirements, now failing cleanly:
A64-EXEC-RWX fails at `VirtualAlloc` with error 5 instead of faulting on execute,
and A64-EXEC-HEAP's `HeapCreate` returns null with error 8. With
`WINEDEBUG=warn+virtual,warn+heap` Wine names the host call:
`mprotect 0x60000000-0x60000fff unix prot 0x7 failed: Permission denied`, and
for heaps `... unix prot 0x7 failed` followed by `Could not commit 0x10000 bytes,
status 0xc0000022`. The same log shows several prefix-startup processes
attempting executable heaps, consistent with the `ntoskrnl_heap` dependency.

The baseline profile is unchanged: `scripts/test-m0.py` on `build/wine-m0`
passes 32/32 (`runs/m0-20261006T164137145138Z`) and the baseline tree's diff
still matches `patches/wine-m0` exactly. The natural write-watch reproducer made
a failure-injection build unnecessary for rollback coverage.

EM-2 exit is met. Remaining: EM-3 must select a host mechanism; the RWX and
heap probes stay failed requirements until EM-4.

Next: EM-3 standalone host experiments; then implement a
mapping policy with real Windows write/execute semantics. Do not infer that a
simple `MAP_JIT` flag solves fixed Windows mappings: Apple's published
[mmap implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_mman.c)
rejects `MAP_JIT` with `MAP_FIXED` and reserves
`MAP_TRANSLATED_ALLOW_EXECUTE` for translated processes. This source is an
integration reference, not proof of the exact installed kernel's behavior.

Further inspection identified two related failure paths, neither yet reproduced
with a dedicated state/leak test:

- `set_vprot` updates Wine's per-page metadata before `mprotect_range` succeeds.
  The latter can protect several runs of pages before a later run fails. A fix
  must account for both metadata and partially changed host protections.
- `dlls/ntdll/heap.c:allocate_region` returns null after a failed commit without
  releasing its successful reservation. Verify reservation growth before
  treating this as a runtime-confirmed leak.

The shared driver dependency is concrete:
`dlls/ntoskrnl.exe/ntoskrnl.c:DllMain` creates `ntoskrnl_heap` with
`HEAP_CREATE_ENABLE_EXECUTE` without checking the returned handle. Restoring
drivers requires this heap to work; adding a null check alone does not meet that
gate.

## Fix plan — planned, not implemented

Work through EM-1–EM-6 sequentially. Each step ends with a small source-generated
patch, its reproducer/result and an updated evidence entry. Current acceptance
is **39/41** on the EM-2 candidate (34/41 before EM-2, initially 33/35); a plan or a graceful allocation failure does not count as
executable-memory support.

### EM-1: measure host failures and Windows state — done except in-Wine diagnostics

Status: host matrix and all five state/leak cases plus the span control are
implemented and recorded above. The opt-in Wine diagnostic patch is folded into
EM-2. The original specification follows.

Extend `tests/m0/runtime.c` and `scripts/test-m0.py` with these isolated cases.
Keep the existing three executable probes as positive requirements.

| Proposed case | Action and oracle |
|---|---|
| A64-EXEC-COMMIT | Reserve 64 KiB, commit one 4 KiB page as RWX; record native NTSTATUS and Win32 error through separate calls. On success, execute/rewrite 42→43. On failure, query the reservation and verify the failed page remains reserved before releasing it. |
| A64-EXEC-PROTECT | Allocate/fill RW, request RWX, query before/after. Success must permit execution; failure must preserve the old data and RW state. Repeat from RX with known executable code. |
| A64-EXEC-ALLOC-FAIL | For a deliberately rejected host protection operation, fresh reserve+commit must fail, leave no new committed/reserved Wine view, and allow reuse of the same address for RW allocation. |
| A64-EXEC-ROLLBACK | Exercise a range with different old protections; force failure after one host protection run succeeds. Verify every page's old protection, contents and commit state through queries and actual accesses. |
| A64-EXEC-HEAP-FAIL | Repeat a targeted executable-heap commit failure after warm-up; count outstanding reservations and bytes, then prove they return to baseline. RSS alone is not a leak oracle. |

Use fresh processes and a checked free address range; fixed-address collisions
must be reported as fixture failures. Log `GetLastError` only on failed Win32
calls. Check `VirtualQuery` state/protection/allocation base, but also perform
read/write/execute probes: metadata alone already gave a misleading result in
A64-EXEC-RWX. Catch intentional faults with exact operation/address checks or
use a separate bounded child. Always release a successful reservation.

Add opt-in diagnostics at the actual host operations in
`dlls/ntdll/unix/virtual.c:mprotect_exec` and the allocation/protection callers:
operation, base, size, requested Windows/Unix protection, saved errno immediately
after failure, returned NTSTATUS, and prior/resulting VM region protections.
Preserve errno across logging. Respect the existing x18 boundary and signal-path
constraints; use bounded, signal-safe capture for diagnostics reachable from
fault handling. Record normal-thread Mach region inspection separately where
needed. Do not change protection behavior in this diagnostic patch.

Natural host refusal is the first reproducer. If needed for deterministic
rollback coverage, add an opt-in diagnostic-build failure injector that targets
only the fixture's address range and selected protection attempt. It must be
disabled by default, bypassed during rollback and absent from acceptance runs
that claim working executable memory.

Also retain a non-injected negative control: a protection request spanning a
committed page and an uncommitted page must fail without changing either page's
protection, as specified by
[Microsoft's VirtualProtect contract](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualprotect).

**Exit:** identify the actual failing host call/errno, reproduce API/state
inconsistency and establish whether failed heap creation leaks reservations.

### EM-2: fix failure propagation and cleanup first — done (39/41)

Implement three reviewable changes only after their EM-1 reproducers fail:

1. In `allocate_virtual_memory`, check the executable `mprotect_range` result.
   For a newly created ordinary private view, undo the view and mapping on
   failure using the existing `delete_view`/`unmap_area` ownership path, then
   return a failure consistent with `set_protection` (currently
   `STATUS_ACCESS_DENIED`). Preserve the original host error for evidence.
   Inspect existing-view, DOS and placeholder paths before applying cleanup;
   deleting an existing reservation is not a valid generic rollback.
2. Make protection changes transactional across Wine metadata and host runs.
   Preserve each old per-page value, including commit, guard and write-watch
   flags; restore changed host runs and metadata if a later operation fails.
   Keep the existing virtual-memory lock/signal discipline. Audit shared
   `set_vprot` callers before changing its contract. A rollback failure needs an
   explicit diagnostic and controlled failure path, never a success return or
   metadata claiming permissions the host does not provide.
3. In `heap.c:allocate_region`, release a reservation owned by that invocation
   when its commit fails, using the verified `NtFreeVirtualMemory` release
   convention. Preserve the original failure and check release status. Cover
   both ordinary heap creation and the large-allocation caller.

**Exit:** injected/natural failures leave consistent state, repeat failures do
not leak reservations, and all 32 console checks plus RW/RX transitions pass.
The RWX positive probe may now fail cleanly at allocation instead of crashing;
it remains a failed requirement. Record this intermediate result explicitly.

### EM-3: choose a host mapping mechanism from standalone experiments

Create a separate native ARM64 VM probe under `tests/` using the existing 4 KiB
spawn/layout/signing setup. Keep P0 independently runnable. Run the following
matrix first at arbitrary addresses, then in an owned low-address reservation
with independent 4 KiB protection tests. Record actual host page size, signatures,
current/max protections, errno or Mach return code, cache flushes and exact
execution results. A 16 KiB control run can diagnose a layout-specific failure;
it cannot satisfy the Wine gate.

| Candidate | Required experiment / selection rule |
|---|---|
| Ordinary anonymous mapping | Compare direct RWX mapping, RW→RWX and RW→RX→RW. Select for Windows RWX only if real accesses at the requested address work, including concurrency. |
| `MAP_JIT` with supported pthread transitions | Run native emit/execute/rewrite and a fresh-thread case. Inspect actual mapping and fixed-address restrictions. Useful for a controlled FEX code cache; successful JIT toggles alone do not satisfy arbitrary Windows heap stores. |
| Shared backing with separate RW and RX aliases | Verify the backing is shared without copy-on-write divergence, updates reach the executable alias after cache maintenance, and allocations can be released/reused. First prove it locally with Mach APIs before proposing Wine integration. |

Apple documents per-thread write/execute switching for its JIT memory model.
That can serve code whose writes the runtime controls; it does not by itself
preserve an unmodified caller's same-address writable/executable contract.
[Apple JIT guidance](https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon)
and the installed SDK's `pthread.h` are the API references. Use the current
signature first; any candidate-specific entitlement experiment gets a separate
binary and recorded signature. No host security setting change or Apple account
approval is a prerequisite for these local experiments.

Madeira is a source reference for the alias experiment:
`app/Madeira/JITAllocator.c:jit_region_create` creates a named memory entry with
RW and RX mappings at snapshot
`bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120`. Its
`build/ntdll-unix/virtual_ios.c:ios_guest_anon_rwx_is_host_data` also contains
iOS/emulator-specific classification and size heuristics. Those are not a valid
classification scheme for this plain ARM64 Wine process.

**Decision gate:** document one proven primitive, address constraints and its
Windows integration contract. If only aliases or controlled JIT writes work,
native same-address RWX remains an architecture gap. Identify the required store
emulation or execution mediation and its cost before designing a larger patch.
Do not select page-wide RW/RX flipping on faults without proving progress and
correctness when one thread executes while another writes. Do not silently drop
execute permission to make driver heap allocation succeed.

### EM-4: integrate the selected contract and stress it

Keep these consumers explicit in the design:

- Native ARM64 Windows executable heaps require guest-visible pointers to retain
  their meaning for direct code execution, ordinary stores and atomics.
- FEX-emitted ARM64 code can potentially use a runtime-controlled code cache.
  Audit allocation, patching, cache publication, unwind/PC lookup and freeing.
- Translated x86 instruction bytes may be data from the host's perspective,
  but Windows protections, self-modifying-code detection and translation
  invalidation still apply. Do not classify memory by allocation size or process
  architecture alone, especially in a mixed ARM64EC process.

The pinned FEX reference is
`be778d7ba5b98bee0405fd1d6a50d305a0807df0`; inspected starting points are
`Source/Windows/Common/WinAPI/Alloc.cpp`,
`Source/Windows/Common/InvalidationTracker.cpp` and
`Source/Windows/ARM64EC/Module.cpp`. This is a follow-on ABI audit, not evidence
that FEX's allocator is compatible with a selected host primitive.

Add bounded tests for two threads executing immutable code and writing separate
data on the **same RWX page**, then synchronized code publication/rewrite across
threads. Avoid unsynchronized modification of instructions being executed.
Include ordinary and atomic writes, at least two adjacent 4 KiB pages with
independent protection, decommit/recommit with zeroed contents, release/reuse,
heap growth/reallocation, and repeated allocation/free without live-view growth.
If the solution introduces aliases, fault handling or per-thread JIT state,
require targeted signal/callback, exception/unwind and thread-start/exit tests
before adoption. Specify how native service writes into guest buffers work.

**Exit:** all existing positive executable probes and the added relevant
semantic/stress tests pass with no failure injection. Keep the 32 console
baseline, no-Rosetta and server-cleanup checks mandatory. File-backed executable
sections, cross-process mappings and mixed guest execution remain explicit later
coverage; anonymous allocation success does not validate them.
The EM-2 failure/rollback tests must also pass in a separate diagnostic run with
their injection settings recorded.

### EM-5: restore the shared kernel heap and drivers

Only after EM-4 passes, build a separate profile with the six driver exclusions
removed from `scripts/build-wine.sh`; use a clean build directory, matching
signing paths and a fresh prefix. The current configure guard rejects old driver
outputs, so update profile/build-directory handling deliberately.

First prove `ntoskrnl_heap` creation and real allocation/use/free. Then restore
NDIS, winebus, winebth, wineusb, mountmgr and nsiproxy in dependency-aware increments.
For each, record actual module loading, required service/driver initialization,
shutdown and one concrete available API/device request. Inspect each driver's
entry/dispatch path to choose that request before claiming validation. A present
binary or quiet startup is insufficient; unavailable hardware coverage remains
pending. Require three fresh-prefix starts and clean shutdowns for the resulting
profile, with no unhandled faults or unrelated-process cleanup.

### EM-6: package reproducible results

Keep the baseline external checkout/build available while testing the candidate.
The current build script verifies an exact single combined patch: generate the
replacement patch from the pinned base and candidate diff, check it against a
clean checkout, and update the script only if the patch layout changes. Never
overwrite an external checkout with unrelated modifications.

Preserve commands, compiler/SDK and source identities, patch hashes, native/PE
binary hashes, signatures, fixture source and harness hashes, prefix IDs,
stdout/stderr, timeouts, expected/observed status and durations. Register required
test IDs explicitly as coverage grows so missing cases cannot pass by matching
a total count. Use the actual successful result set to update this report,
`docs/milestones.md` and the README; retain the original 33/35 failure evidence.

**Immediate next implementation package:** EM-3 — extend
`tests/exec-memory/host-vm-probe.c` with `MAP_JIT` and shared-alias candidates
and evaluate Wine's existing write-exception mode, then choose a primitive. EM-3 selects the mapping
mechanism; its outcome must precede a writable/executable implementation claim.
