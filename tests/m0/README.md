# M0 Windows ARM64 acceptance tests

Run `scripts/build-wine.sh`, then `scripts/test-m0.py`. Build products, prefixes, logs and JSON results stay under `$AOE2_WORK_ROOT` (default `$HOME/aoe2-poc-work`). The runner compiles plain ARM64 PE probes with LLVM/MinGW, inspects machine headers, uses a new prefix, applies deadlines and captures exact exit status/stdout/stderr. It kills only the wineservers associated with its own prefixes at cleanup, then waits for each to exit. A hung server fails acceptance.

The existing `tests/hello-a64/a64_hello.c` is retained: fixed output `A64-HELLO OK`, nonzero Windows PID/TID, and exit 23. `runtime.c` provides separate cases for 4 KiB memory/protection and a real access fault, shared-user-data mapping/time, eight distinct-TEB TLS/atomic workers (80,000 total increments), locale callbacks with native process-time and precise-clock calls, application/access-violation SEH, and Unicode file I/O with exact bytes. A separate unhandled access fault must terminate with exit 5 and the exact fault address; an interactive debugger is disabled only for that negative fixture. A failed check returns nonzero. SEH uses `-fms-extensions -Xclang -fasync-exceptions`: the MinGW driver ignores the plain `-fasync-exceptions` switch, so the frontend option is required to preserve hardware-fault handler ranges. Application exception and write-fault codes, addresses, and PC are checked.

The precise-clock call crosses the actual `unix_system_time_precise` entry. An opt-in native diagnostic checks page size/custom mode there; the runner requires its marker in the callback case. This supplements syscall-boundary diagnostics.

Repeat acceptance runs hello 20 times and once in an independently initialized prefix. Native output records actual 4096-byte host pages, disabled custom-x18 mode inside the native service boundary, and no process translation. The runner additionally rejects host executables that are not thin ARM64 Mach-O files. Runtime libraries execute inside this ARM64 process; an x86-64 native library cannot satisfy that ABI.

This is M0, not an x64/FEX, graphics, Steam, or multiplayer test. Results are machine-specific. The implementation still needs M1/M1.5 stress tests of mixed execution, nested callbacks, asynchronous signals, thread suspension and genuine child-process IPC before using Steam.

The M0 build deliberately omits NDIS, winebus, winebth, wineusb, mountmgr and nsiproxy device drivers.
Their executable heaps currently fail on this host. They are outside console M0;
resolve executable memory and restore/test the drivers before broader runtime work.

Run `scripts/test-m0.py --exec-memory` for the 32 baseline checks plus three
executable-memory probes. This extension remains a failing acceptance gate:
`exec-heap` creates an executable heap and runs/replaces ARM64 code;
`exec-rwx` allocates at `0x60000000` with read/write/execute permissions and
runs/replaces code; `exec-transition` writes with RW permissions, changes to RX,
runs, returns to RW to rewrite, then changes to RX and runs again. Each successful
execution must return exactly 42 then 43 after instruction-cache flushes.
Six EM-1 state cases (`exec-commit`, `exec-protect`, `exec-alloc-state`,
`exec-rollback`, `exec-protect-span`, `exec-heap-leak`) accept success or failure
of an executable request but require `VirtualQuery` state to match real accesses
and failed executable heaps not to leak reservations; the mode requires 41 checks.
Set `AOE2_WINE_PROFILE=em` to test the executable-memory candidate build
(`build/wine-em`) instead of the M0 baseline; run directories are named by profile.
An interactive debugger is disabled for these probes so an unexpected fault
terminates within the test deadline. See [results](../../docs/executable-memory.md).
