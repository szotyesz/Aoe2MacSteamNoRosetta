# AoE2DE on Apple Silicon without Rosetta

Local proof of concept for running Windows Steam and Age of Empires II: Definitive Edition through native ARM64 Wine, FEX CPU translation, and DXMT Metal rendering. Work proceeds on a temporary SIP/AMFI-disabled installation while the user investigates entitlement access with Apple. Apple's approval is not a prerequisite for this local POC.

## Verified status — 2026-10-06

The native host capability smoke tests pass on **macOS 26.6.2 (25G83), SDK 27.0**, with SIP disabled and boot argument `amfi_get_out_of_my_way=0x1`:

| Capability | Result |
|---|---|
| Spawn children with 4 KiB pages; protect an individual 4 KiB page | PASS |
| Remap low-address memory at `0x7ffe0000` using layout emulation | PASS |
| Enter custom x18 ABI mode, write/read x18, and return to macOS mode | PASS |
| Enable/disable TSO on the main thread and a fresh pthread | PASS |

Run the tests from the repository root:

```sh
./scripts/test-platform.sh
```

The script builds a native ARM64 executable in a temporary directory, ad-hoc signs it with `com.apple.developer.cross-architecture-support-unmanaged`, runs isolated test children, and removes the build outputs. The entitlement must be present in the signature on this host; successful execution does not establish Apple account authorization or operation with SIP/AMFI enabled.

The test targets macOS 26.5 but has only been verified on 26.6.2. See [test coverage and limitations](tests/platform/README.md).

## M0 console runtime — PASS

Native ARM64 Wine now executes plain Windows ARM64 PE programs with a separate
native wineserver. **32/32 checks pass**: exact hello output/exit 23, individual
4 KiB memory protection, shared-user-data time, eight concurrent TLS/TEB workers,
callbacks across native syscall and Unix-call boundaries, handled and unhandled
exceptions, Unicode file I/O, 20 repeated launches, a fresh prefix, native host
execution, and server shutdown. The platform smoke tests still pass unchanged.

Reproduce from the repository root:

```sh
./scripts/build-wine.sh
./scripts/test-m0.py
```

The build uses the installed LLVM/MinGW toolchain under `$AOE2_WORK_ROOT`
(default `$HOME/aoe2-poc-work`); source acquisition/toolchain details are in
[toolchains](docs/toolchains.md). It uses Wine 11.4's pinned upstream base with
[audited local changes](patches/wine-m0/README.md). Sources, build products and
fresh test prefixes stay outside this repository. Existing Madeira reference
checkouts are preserved. The runner records deadlines, exact exit statuses,
stdout/stderr, source/compiler identity and binary hashes.

This is a **console-only profile**. NDIS, winebus, winebth, wineusb, mountmgr and
nsiproxy drivers are disabled because Windows executable-heap commit fails on
this host and their unchecked heap use crashes startup. Device support, those
network/drive-management services, FEX, DXMT, Steam and AoE2DE are not validated.
Apple entitlement access remains a parallel inquiry, not a local POC blocker.

Next (route revision R1, see [route review](docs/route-review.md)): re-port the
M0 and EM patches from Wine 11.4 to the upstream wine-11.19 tag, fixing an x18
signal race and other defects found in review; then make the ntoskrnl heap
non-executable to restore the six drivers, and run the EM-3 host experiments.
Native simultaneous writable+executable memory is no longer a goal: macOS
refuses it for non-JIT memory, so executable memory is split by consumer (plan
section M0-EM). FEX and DXMT move to upstream pins; Madeira is a reference only.
The [executable-memory probes](docs/executable-memory.md) record EM-1 (host RWX
refused with EACCES) and EM-2 (`AOE2_WINE_PROFILE=em`, 39/41 checks).
See [M0 results and preserved evidence](docs/m0-results.md),
[the detailed plan](aoe2de-no-rosetta-plan.md),
[milestone status](docs/milestones.md), and
[entitlement observations](docs/entitlement-audit.md).
