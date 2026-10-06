# AoE2DE on Apple Silicon without Rosetta

Local proof of concept for running Windows Steam and Age of Empires II: Definitive Edition through native ARM64 Wine, FEX CPU translation, and DXMT Metal rendering. Work proceeds on a temporary SIP/AMFI-disabled installation while the user investigates entitlement access with Apple. Apple's approval is not a prerequisite for this local POC.

## Verified status — 2026-10-05

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

## Implementation status and next step

Only the host capability tests are implemented and verified. Wine, FEX, DXMT, Steam, and AoE2DE execution remain pending. The malformed patch drafts, incorrect Wine build script, placeholder loader, unverified Windows probe, and stale audit/status claims have been removed.

Next: complete P1.1–P1.2 in [the detailed implementation plan](aoe2de-no-rosetta-plan.md): record native toolchains, inspect actual Wine ARM64 macOS support, and compare the pinned Madeira Wine/FEX/DXMT integration with upstream. Select a source combination before creating patches. The proposed route keeps separate macOS Wine processes and reuses compatible Madeira components selectively. Then verify native Darwin and Windows PE compiler probes and build the first ARM64 Windows console runtime test.

See [the POC plan](aoe2de-no-rosetta-plan.md), [milestone status](docs/milestones.md), and [entitlement observations](docs/entitlement-audit.md).
