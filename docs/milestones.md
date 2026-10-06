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

Next (route revision R1): re-port M0/EM from Wine 11.4 to upstream wine-11.19
(plan M0.0), fixing the x18 signal race, hot-path diagnostics, 4 KiB re-spawn,
TSO scope and CPU feature reporting. Then restore NDIS, winebus, winebth, wineusb,
mountmgr and nsiproxy with a non-executable ntoskrnl heap, and run the EM-3 host
experiments under the executable-memory design in plan section M0-EM. The
[executable-memory probes](executable-memory.md) record EM-1 (host refuses RWX
with EACCES) and EM-2 (39/41 extended checks). New gates: M1.6 (i386/WoW64),
S1 (signing profile with SIP/AMFI enabled) and T1 (winetest lanes). See
[the detailed plan](../aoe2de-no-rosetta-plan.md) and the
[route review](route-review.md).
