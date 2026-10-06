# Local POC milestone status

Updated: 2026-10-06. Entitlement access is being queried with Apple in parallel and does not block work on the temporary SIP/AMFI-disabled installation.

| Stage | Status | Evidence / next requirement |
|---|---|---|
| P0: platform capability probe | PASS on this host | `scripts/test-platform.sh`: 4 KiB pages, low mapping, x18, main/fresh-thread TSO; macOS 26.6.2, SDK 27.0 |
| P1: toolchain/source audit | Ready for M0; M1 combination still pending | Native/PE compiler probes pass; exact reference commits recorded. Madeira Wine full build exposed iOS-only hooks; M0 uses Wine 11.4 upstream base plus the local patch. Full ARM64EC/FEX ABI selection remains M1. |
| M0: native ARM64 Wine console | **PASS, 32/32 checks** | [Raw results](evidence/m0/results.json), [coverage and limitations](m0-results.md); six device drivers excluded because executable heaps fail |
| M1: FEX x86-64 execution | Pending | EC-CALL and X64 execution/CPU/FP/memory/exception/backend tests |
| M1.5: local runtime integration | Pending | Genuine process isolation, IPC, synchronization, networking, and clean-prefix tests; mixed children after x86 support |
| M1.6: i386 through WoW64 | Pending | X86 probes, large-address-aware layout, suspend, PROC-MIXED, winetest i386 lane |
| M2: Windows Steam | Pending | Genuine Steam client/login/UI/download/restart; Dock tracked separately |
| M3: D3D11 and game menu | Pending | D11 numerical readback/resource/lifecycle tests and three cold menu launches |
| M4: gameplay | Pending | Three repeatable runs, 30-minute play, save/reload, media/input and measured frame times |
| M5: Windows multiplayer | Pending | Three completed Windows-peer sessions, including a 30-minute session; no observed desync |

M0 proves native ARM64 Windows console execution through Wine. It does not prove
x64 translation, executable heaps, the excluded device/network services, graphics,
Steam or AoE2DE. The original platform probe remains unchanged and passes.

**Plan R2 (2026-10-06):** the stages above (P0–M5) describe the archived R1 plan
(`docs/archive/plan-r1-own-wine.md`). P0 and M0 results remain valid evidence for
macOS 26.6.2. Work now follows the R2 stages in [the plan](../aoe2de-no-rosetta-plan.md):

| Stage | Status |
|---|---|
| N0: released MacNeutron + AoE2DE on macOS 27 | Pending (needs macOS 27) |
| N1: fork builds here, non-Rosetta gates pass | Pending |
| N2: audit with this project's tests | Pending |
| N3: AoE2DE single-player | Pending |
| N4: Windows-peer multiplayer | Pending |
| N5: 32-bit, D3D9, media, regression lanes, optional Windows Steam | Pending |
