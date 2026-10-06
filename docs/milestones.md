# Local POC milestone status

Updated: 2026-10-06. Entitlement access is being queried with Apple in parallel and does not block work on the temporary SIP/AMFI-disabled installation.

| Stage | Status | Evidence / next requirement |
|---|---|---|
| P0: platform capability probe | PASS on this host | `scripts/test-platform.sh`: 4 KiB pages, low mapping, x18, main/fresh-thread TSO; macOS 26.6.2, SDK 27.0 |
| P1: toolchain/source audit | Ready for M0; M1 combination still pending | Native/PE compiler probes pass; exact reference commits recorded. Madeira Wine full build exposed iOS-only hooks; M0 uses Wine 11.4 upstream base plus the local patch. Full ARM64EC/FEX ABI selection remains M1. |
| M0: native ARM64 Wine console | **PASS, 32/32 checks** | [Raw results](evidence/m0/results.json), [coverage and limitations](m0-results.md); six device drivers excluded because executable heaps fail |
| M1: FEX x86-64 execution | Pending | EC-CALL and X64 execution/CPU/FP/memory/exception/backend tests |
| M1.5: local runtime integration | Pending | Genuine process isolation, IPC, synchronization, networking, and clean-prefix tests; mixed children after x86 support |
| M2: Windows Steam | Pending | X86 probes, PROC-MIXED, genuine Steam client/login/UI/download/restart; Dock tracked separately |
| M3: D3D11 and game menu | Pending | D11 numerical readback/resource/lifecycle tests and three cold menu launches |
| M4: gameplay | Pending | Three repeatable runs, 30-minute play, save/reload, media/input and measured frame times |
| M5: Windows multiplayer | Pending | Three completed Windows-peer sessions, including a 30-minute session; no observed desync |

M0 proves native ARM64 Windows console execution through Wine. It does not prove
x64 translation, executable heaps, the excluded device/network services, graphics,
Steam or AoE2DE. The original platform probe remains unchanged and passes.

Next: solve the executable-memory contract and restore/test NDIS, winebus,
winebth, wineusb, mountmgr and nsiproxy before broader application work. In
the [focused executable-memory probes](executable-memory.md), explicit RW/RX
transitions pass; executable heaps and RWX execution still fail (34/41). EM-1
identified host EACCES for RWX, inconsistent Wine protection state and a
failed-heap reservation leak; the EM-2 candidate profile fixes those failure
paths (39/41); EM-3 selects a host mechanism for real RWX semantics next. In
parallel, the next source task is M1's concrete ARM64EC/FEX ABI map and selection;
Madeira's iOS runtime assumptions still require individual adaptation. See
[the detailed plan](../aoe2de-no-rosetta-plan.md) for explicit tests and gates.
