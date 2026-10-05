# Local POC milestone status

Updated: 2026-10-05. Entitlement access is being queried with Apple in parallel and does not block work on the temporary SIP/AMFI-disabled installation.

| Stage | Status | Evidence / next requirement |
|---|---|---|
| P0: platform capability probe | PASS on this host | `scripts/test-platform.sh`: 4 KiB pages, low mapping, x18, main/fresh-thread TSO; macOS 26.6.2, SDK 27.0 |
| P1: toolchain/source audit | Pending | Verify upstream implementations, pin exact revisions, and select ARM64EC build tools |
| M0: native ARM64 Wine | Pending | Build native Wine and execute an ARM64 Windows console probe |
| M1: FEX x86-64 execution | Pending | Repeated x64 probe execution and FEX evidence |
| M1.5: local runtime integration | Pending | Clean prefix, children, thread setup, repeatable commands |
| M2: Windows Steam | Pending | Mixed architectures, helpers, login, downloads, test launch |
| M3: D3D11 and game menu | Pending | DXMT rendering probe and stable AoE2DE menu |
| M4: gameplay | Pending | Single-player stability and recorded performance |
| M5: Windows multiplayer | Pending | Repeat completed matches without desyncs |

The platform result is a smoke test, not evidence that the compatibility runtime works. No Wine/FEX/DXMT runtime milestone is complete. Follow the detailed acceptance criteria in `aoe2de-no-rosetta-plan.md`.
