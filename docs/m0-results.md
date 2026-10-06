# M0 native ARM64 console acceptance

Verified 2026-10-06 on macOS 26.6.2 (25G83), Apple Silicon ARM64, SDK 27.0.
SIP is disabled; boot arguments contain `amfi_get_out_of_my_way=0x1`.
**PASS: 32/32 checks; `scripts/test-m0.py` exits 0.** The original
`scripts/test-platform.sh` also passes, with its files unchanged.

## Reproduce

```sh
./scripts/build-wine.sh all
./scripts/test-m0.py
```

Prerequisites and native/PE toolchain acquisition are recorded in
[toolchains](toolchains.md) and `sources.lock.json`. Both scripts use
`$AOE2_WORK_ROOT`, default `$HOME/aoe2-poc-work`. `prepare`, `configure`, and
`make` are also separate build-script steps. Reconfiguration rejects stale
outputs from excluded drivers; preserve an older build directory and start a
clean one rather than mixing profiles.

The build uses Wine 11.4 at `cc893ef9cb17b994bfd1f1a1f7355be55e615623` with
[the native macOS patch](../patches/wine-m0/README.md). It builds a thin ARM64
Mach-O loader, a separate thin ARM64 wineserver, native ARM64 libraries, and
plain ARM64 PE modules. Probes inspect as ARM64 (0xAA64). FEX and Rosetta are
not used. Native execution is checked in the executing Wine process through
`sysctl.proc_translated`, as well as host executable architecture inspection.
The main Wine loader is ad-hoc signed with the unmanaged cross-architecture
entitlement. Wineserver and native libraries receive ordinary ad-hoc signatures.

## Exact acceptance results

| Check | Result / oracle |
|---|---|
| A64-HELLO | PASS; exact `A64-HELLO OK`, nonzero Windows PID/TID, exit 23 |
| A64-MEM | PASS; 4096-byte Windows pages; independent page protections; write to protected page catches exact AV/address/PC; free succeeds |
| A64-SHARED | PASS; committed shared data at `0x7ffe0000`; stable high/low/high time read advances and agrees with Windows API time |
| A64-THREAD | PASS; eight concurrent distinct TEBs, stable per-thread TLS/TEB across calls/yields, exactly 80,000 atomic increments; every thread exits 0 |
| A64-CALLBACK | PASS; locale enumeration invokes callbacks; process-time syscall and precise-clock Unix call succeed; callback failures counted and required to be zero; guest TEB stays stable |
| A64-SEH | PASS; application exception `0xe0424242` handled; write AV at `0x1234` has correct code/access/address/PC; execution continues |
| A64-IO | PASS; Unicode/spaced filename; exact binary bytes written/read; handles closed and file removed |
| A64-SEH-UNHANDLED | PASS; separate write at `0x1234` terminates with exit 5 and exact unhandled-fault address; interactive debugger disabled only for this negative fixture |
| A64-REPEAT-01–20 | PASS; every fresh client returns exact hello output and exit 23 from one dedicated prefix |
| A64-FRESH | PASS; independently initialized second prefix returns exact output and exit 23 |
| HOST-NATIVE | PASS; native diagnostics report actual 4096-byte host pages, custom x18 disabled and no translation; Unix-clock diagnostic required in callback case |
| SERVER-CLEANUP-prefix / fresh-prefix | PASS; each dedicated server is stopped or already absent, and an independent `-w` check returns 0 within its deadline |

All successful probes exit 0 except hello/repeat/fresh (23) and the deliberate
unhandled-fault fixture (5). Any unexpected unhandled exception in an ordinary
case fails acceptance. The harness uses fresh isolated prefixes, explicit
loader/server paths, deadlines, and removes inherited Wine override variables.
It preserves exact exit statuses and output, including failed runs, outside the
repository. Wine `-k` returns 1 when no lock owner remains; cleanup accepts that
only with no error output and a successful independent shutdown wait.

## Evidence

The successful run is
`$AOE2_WORK_ROOT/runs/m0-20261006T052156671425Z`.
[Raw results](evidence/m0/results.json) retain every check, command, working
path, timestamp, duration, timeout result, compiler identity, source/patch/lock
hash, and executed binary hash. The corresponding stdout/stderr logs, PE header
inspection, cleanup logs and embedded entitlement are preserved alongside it.
[Build evidence](evidence/m0/build-evidence.json) records the native compiler
and hashes/paths of the external configure/build logs.

The final patch was checked/applied against pristine copies of all six affected
base files and reproduced the exact modified source. Idempotent `prepare`,
shell/Python syntax, source-lock agreement, expected excluded-driver absence,
thin host architectures, signatures and repository whitespace were checked.

## Failures resolved and limits retained

The pinned Madeira Wine fork configures but does not link native `win32u.so`
without iOS-only source-watch hooks. Its reference checkout is preserved; M0
uses the upstream base, not invented replacements for those hooks.

SDK 27 exposes `pipe2` as a weak import, but this macOS runtime lacks it. A
link-only configure probe selected it and the first native launch called address
zero. The recipe forces the existing `pipe`/`fcntl` fallback, sets deployment
26.5, and rejects unguarded newer API calls at compile time. Execution on macOS
26.5 itself is still unverified.

Darwin protection faults can arrive as SIGBUS. The ARM64 handler now distinguishes
alignment faults (ESR DFSC 0x21) from the Windows access-violation path. Hardware
fault fixtures use `-Xclang -fasync-exceptions` because the MinGW driver ignores
the plain async-exception switch; otherwise handler ranges were optimized away.
Thread tests use a start event so TEB uniqueness is checked among simultaneously
live threads, rather than incorrectly rejecting legitimate reuse after exit.

**The profile excludes six device drivers:** NDIS, winebus, winebth, wineusb,
mountmgr and nsiproxy. `HeapCreate(HEAP_CREATE_ENABLE_EXECUTE, 0, 0)` fails on
this host; unchecked use in driver code then faults inside `RtlAllocateHeap` at
null + 0x8a0. Executable-memory entitlement experiments did not fix it and are
not retained. The console tests do not validate device support, drive-management
services or the nsiproxy networking path. This is not a general Wine/Steam
runtime, and no allocation/API is replaced with fake success.

Next: implement and test a real executable-memory contract; restore/test each
excluded driver with fresh-prefix startup free of unhandled faults. M1 separately
requires the ARM64EC/FEX ABI map and JIT write/execute contract. Nested framework
callbacks, asynchronous signals, suspension/context changes, transition-helper
unwinding, mixed execution, networking, graphics, Steam and AoE2DE remain later
gates. Apple's account entitlement approval is a parallel inquiry and does not
block this local console POC.
