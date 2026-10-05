# macOS cross-architecture capability smoke test

From the repository root:

```sh
./scripts/test-platform.sh
```

Requires native Apple Silicon macOS 26.5+, a SDK declaring the APIs, and a linker supporting `-x86_64_layout_emulation`. This test is for the temporary SIP/AMFI-disabled POC installation. It does not change system settings. It builds in a temporary directory, ad-hoc signs with the unmanaged cross-architecture entitlement, verifies the signature, and deletes the artifacts on exit. A plist entitlement is not proof of account authorization.

Three isolated children use 4 KiB spawning and report PASS/FAIL with exit/signal details. The memory case checks both page-size reports, remaps the PAGEZERO reservation at `0x7ffe0000`, writes two adjacent 4 KiB pages, and changes protection on the second page. The x18 case masks signals and uses an assembly helper to write/read the register only between custom ABI API transitions. The TSO case checks kernel enable/disable results on the main thread and on a fresh pthread, explicitly initializing each.

The x18 case tests mode transitions and register access, not preservation across context switches, signal delivery, or Wine callbacks. The TSO case tests API acceptance, not hardware memory ordering or inheritance. The memory case checks protection-call acceptance, not a fault on a prohibited write. This probe does not test ARM64EC dispatch, JIT execution, Wine, FEX, DXMT, or Steam. Those need the plan's later integration tests.

Verified 2026-10-05: macOS 26.6.2 (25G83), SDK 27.0, SIP disabled, `amfi_get_out_of_my_way=0x1`: all cases pass. No execution on 26.5 has been verified.

Use a 4 GiB PAGEZERO with this toolchain. The earlier proposed `0x170000000` produced a linker truncation warning and 4 KiB spawn failures (`Malformed Mach-o file`); a small PAGEZERO also failed locally. The chosen layout passes the low-address remapping test. Removing the entitlement from the ad-hoc signature caused launch failure on this host, so the test keeps it even under the current relaxed enforcement.

The [Wine announcement](https://list.winehq.org/hyperkitty/list/wine-devel%40list.winehq.org/message/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/) identifies x18, 4 KiB pages, remappable PAGEZERO, and per-thread TSO as the necessary host facilities. SDK availability annotations differ from that announcement (x18 26.4, 4 KiB spawning 26.0); layout is described as 26.4. The test targets the full set available by 26.5. The SDK's newer `os_cross_arch_is_supported()` query requires 26.6 and is deliberately excluded from the 26.5 probe.
