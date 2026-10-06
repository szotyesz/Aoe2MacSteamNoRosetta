# Native ARM64 macOS console patch

Base: Wine 11.4, `cc893ef9cb17b994bfd1f1a1f7355be55e615623`.
Apply using `scripts/build-wine.sh prepare`. The file is an exact `git diff --binary`
from that base; prepare verifies HEAD and the complete patch, and refuses unrelated edits.

- Configure selects a native ARM64 loader without the x86 preloader. Only the main
  executable receives layout-emulation/PAGEZERO linker settings. The reservation
  from `0x10000` through `0xffffffff` is reported through `wine_main_preload_info`;
  Wine's own VM allocator owns subsequent remapping.
- A loader started with 16 KiB pages re-spawns itself using the 4 KiB spawn API,
  waits for that child, and propagates its status. It enters Wine only with 4 KiB
  pages. Loader routes for later Wine processes use the same entry point.
  Wineserver stays a native ordinary-page process; it does not map Windows memory.
- ARM64 syscall and Unix-call assembly disables custom x18 mode before native C
  and restores it before guest return. Transition helpers preserve x0–x17, LR,
  NZCV, all vector registers, FPCR and FPSR. Guest x18 comes from the Wine frame;
  native x18 is owned by Apple's API. Call-user-mode callbacks use the same boundary.
- Signal wrappers leave custom mode for native handling and re-enter for restored
  guest contexts. Darwin SIGBUS protection faults take the access-violation path;
  ESR DFSC 0x21 retains the alignment-fault path.
- Executing guest threads initialize TSO and check the kernel result.
- `AOE2_M0_DIAGNOSTICS=1` records VM reservations, thread setup, native page size
  and translation state. Native boundary invariants are checked on every service
  transition. The existing precise-clock Unix entry provides an opt-in callback
  diagnostic, rather than a synthetic Windows API returning success.

The patch intentionally targets the local 26.5+ POC. The recipe currently omits
six device drivers because writable/executable heap commit fails on this host.
The patch does not implement an FEX JIT allocator or claim executable-heap support.
The baseline console tests are not exhaustive validation of asynchronous signals,
nested framework callbacks, context switching, unwind metadata or mixed ARM64EC/x64
execution. Those are explicit later gates. Both signal wrappers and assembly helper
unwind behavior need that stress coverage before larger applications.
