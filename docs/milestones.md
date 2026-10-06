# Local POC milestone status

Updated: 2026-10-06. Entitlement access is being queried with Apple in parallel and does not block work on the temporary SIP/AMFI-disabled installation.

| Stage | Status | Evidence / next requirement |
|---|---|---|
| P0: platform capability probe | PASS on this host | `scripts/test-platform.sh`: 4 KiB pages, low mapping, x18, main/fresh-thread TSO; macOS 26.6.2, SDK 27.0 |
| P1: toolchain/source audit | **Complete** (P1.1–P1.4 done) | P1.1 inventory + P0-BASE re-run PASS (`docs/toolchains.md`); P1.2 fetch/verify/inspect + route proposal (`docs/source-selection.md`); P1.3 `scripts/check-toolchains.sh` 10/10 (TC-HOST native; TC-A64/EC/X64/X86 PE machines incl. ARM64EC 0xA641); P1.4 `sources.lock.json` + `scripts/fetch-sources.sh` 6/6 + build recipes. **Exit met:** selected Wine host `./configure --enable-archs=arm64ec --without-freetype` SUCCEEDS on the Darwin host (arm64ec + x86_64 PE, `wineserver` + `ntdll`-arm64ec rules) — see `docs/toolchains.md` P1.3. |
| M0: native ARM64 Wine | Pending | A64-HELLO/MEM/SHARED/THREAD/CALLBACK/SEH/IO/REPEAT and HOST-NATIVE |
| M1: FEX x86-64 execution | Pending | EC-CALL and X64 execution/CPU/FP/memory/exception/backend tests |
| M1.5: local runtime integration | Pending | Genuine process isolation, IPC, synchronization, networking, and clean-prefix tests; mixed children after x86 support |
| M2: Windows Steam | Pending | X86 probes, PROC-MIXED, genuine Steam client/login/UI/download/restart; Dock tracked separately |
| M3: D3D11 and game menu | Pending | D11 numerical readback/resource/lifecycle tests and three cold menu launches |
| M4: gameplay | Pending | Three repeatable runs, 30-minute play, save/reload, media/input and measured frame times |
| M5: Windows multiplayer | Pending | Three completed Windows-peer sessions, including a 30-minute session; no observed desync |

The platform result is a smoke test, not evidence that the compatibility runtime works. No Wine/FEX/DXMT runtime milestone is complete. Follow the detailed acceptance criteria in `aoe2de-no-rosetta-plan.md`.

The expanded plan defines test IDs, execution evidence, and source-selection gates. All new test ideas are planned, not implemented. Madeira is an integration reference; no Madeira runtime component has been built here. P1.2 fetched and verified the four pinned sources and produced a route proposal (`docs/source-selection.md`); P1.4 has now **locked the route** via `sources.lock.json` + `scripts/fetch-sources.sh` (all four at plan-§16 pins, LLVM toolchain SHA-256 verified) and written the build recipes (`scripts/build-{wine,fex,dxmt}.sh`). The selected Wine host `./configure` succeeds, but no `make`/FEX/DXMT build has been run and no runtime milestone is complete — M0 (native ARM64 Wine, A64-HELLO) is the next gate and starts only on explicit authorization.
