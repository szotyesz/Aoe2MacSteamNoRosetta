# Source selection and native macOS route

Updated: 2026-10-06. The lock file records exact sources and toolchain inputs. A configure pass alone does not prove a working Darwin runtime.

**Superseded by plan R2 (MacNeutron base). Route revision R1 (2026-10-06):** the selected sources from M0.0 onward are upstream Wine `wine-11.19` (`455e3509b98a`), upstream FEX main at or after `f18599d09`, and upstream DXMT main at or after `e94c312`. Madeira and its forks are references only. See plan section 3.0 and `docs/route-review.md`. The text below records the M0 decision on Wine 11.4 and remains accurate for that profile.

## Reference sources

| Component | Inspected commit | Purpose |
|---|---|---|
| Madeira | `bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120` | Build/interface reference |
| Madeira Wine fork | `3a54f56896c85c932870afe6fd91404bbbcb74c8` | ARM64EC integration reference for M1 |
| Madeira FEX fork | `be778d7ba5b98bee0405fd1d6a50d305a0807df0` | Emulator backend candidate for M1 |
| Madeira DXMT fork | `8937c08c38f5cb867d995f99b2323739a9f6ffdf` | Graphics ABI reference for M3 |

The earlier P1 document contained incorrect expanded commit IDs and repository URLs. The IDs above are the actual fetched objects and match `sources.lock.json`; nested dependencies still require per-build verification.

## M0 source decision

The original Madeira fork configures on Darwin with ARM64EC PE modules, but its full build fails linking `win32u.so`: `_ios_srcwatch_arm`, `_ios_srcwatch_arm_geom`, and `_winios_dump_srcbits` require iOS app services. Standard source filenames therefore do not imply iOS-independent behavior.

For M0, use **Wine 11.4's upstream base**, `cc893ef9cb17b994bfd1f1a1f7355be55e615623`, present in the fetched fork history. A separate checkout under `$AOE2_WORK_ROOT/sources/wine-m0` preserves the Madeira reference. Build native ARM64 Darwin host code and plain Windows ARM64 PE modules, with a genuine separate wineserver. No FEX, ARM64EC, DXMT, fake API success, or iOS pseudo-process services are needed for M0.

The local patch adds the entitled loader address layout, 4 KiB re-spawning, guest/native custom-x18 boundaries and signal-mode transitions, per-thread TSO initialization, and optional runtime diagnostics. It is generated from the real base; scripts verify the exact patch and refuse to overwrite unrelated source edits.

SDK 27's `pipe2` declaration is newer than the running macOS 26.6 runtime. Wine's link-only configure test accepts it as a weak import and then calls a null address at runtime. The M0 recipe forces `ac_cv_func_pipe2=no` to select existing `pipe` + `fcntl` paths, and treats unguarded newer-API use as a compilation error. The deployment target is 26.5 for native compile and link.

The console profile disables NDIS, winebus, winebth, wineusb, mountmgr and nsiproxy.
Their shared ntoskrnl executable heap cannot commit RWX memory on this host; the
unchecked null heap faults at offset 0x8a0 in RtlAllocateHeap. Console tests need
none of these drivers. Disabling them is an explicit scope limit, not a replacement
implementation of executable memory or device/network APIs. Adding the standard
unsigned-executable-memory entitlement, with and without the hardened-runtime
flag, did not make the executable-heap reproducer pass, so neither experiment is
part of the final signing recipe. Restore/test those services after a genuine
executable-memory implementation.

M1 must re-evaluate which ARM64EC/FEX changes to adopt against this base. The old ARM64EC configure result and presence of emulator module targets do not prove that M1 integration is complete. M3 must separately select compatible ARM64EC/native macOS DXMT components; no null graphics API is used to claim graphics success.

## Reproduce

```sh
./scripts/fetch-sources.sh
./scripts/build-wine.sh
./scripts/test-m0.py
```

`build-wine.sh` supports `prepare`, `configure`, and `make` separately. It preserves the reference source directories, builds out of tree, stops on build errors before signing, and uses native host compilers independently from the Windows PE toolchain. See `docs/m0-results.md` for the actual acceptance result; this source choice alone is not an M0 pass.
