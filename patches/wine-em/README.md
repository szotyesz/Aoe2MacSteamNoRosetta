# Executable-memory candidate patch (EM-2)

Base: Wine 11.4, `cc893ef9cb17b994bfd1f1a1f7355be55e615623`. The file is one exact
`git diff --binary` from that base: the complete M0 patch
(`patches/wine-m0/`, unchanged) plus the EM-2 changes below. Build it in its own
source and build trees with `AOE2_WINE_PROFILE=em scripts/build-wine.sh`, and
test with `AOE2_WINE_PROFILE=em scripts/test-m0.py --exec-memory`. The M0
baseline profile and its trees are not touched.

EM-2 makes failed executable-memory requests fail cleanly. It does **not** add
writable+executable support; the host refuses RWX with EACCES
(`docs/executable-memory.md`), so the positive RWX and executable-heap probes
still fail, now at allocation instead of with a crash.

- `dlls/ntdll/unix/virtual.c:set_vprot` saves the per-page protection bytes of
  the range before changing them. If `mprotect_range` fails, it restores those
  bytes and reapplies them to the host, undoing earlier host runs that already
  changed, and returns failure with the original errno. A failed restore is
  logged with `ERR`. Every `set_vprot` caller therefore keeps metadata that
  matches the host, including `set_protection` (commit and `NtProtectVirtualMemory`).
- `map_view` restores the view's protection and returns `STATUS_ACCESS_DENIED`
  when replacing a placeholder fails.
- `allocate_virtual_memory` no longer ignores the host protection result for a
  new executable reservation: it deletes the new view through `delete_view`
  (which also returns the area to Wine's reserved range) and returns
  `STATUS_ACCESS_DENIED`, consistent with `set_protection`. Replaced placeholders
  skip the duplicate host call because `map_view` already applied it.
- `mprotect_range` logs the failing host range, Unix protection and errno with
  `WARN` (opt-in through `WINEDEBUG=warn+virtual`) and preserves errno.
- `dlls/ntdll/heap.c:allocate_region` releases its own reservation with
  `NtFreeVirtualMemory(MEM_RELEASE)` when the commit fails, logging a failed
  release with `ERR`. This covers heap creation, subheap growth and large blocks.

Image mappings use `set_vprot` too. A writable+executable section that the host
refuses now keeps its previous, accurately reported protection instead of
claiming execute permission it does not have. Translated (FEX) images will
need the write-exception mode or another EM-3 mechanism for such sections.
