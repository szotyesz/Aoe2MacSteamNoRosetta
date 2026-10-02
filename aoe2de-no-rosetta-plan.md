# AoE2DE on Apple Silicon Without Rosetta

Updated: 2026-10-02. This is an implementation plan, not a record of completed runtime milestones.

## Goal

Run the **Windows Steam version of Age of Empires II: Definitive Edition** on Apple Silicon macOS with:

- no Rosetta 2
- Windows multiplayer compatibility
- native-feeling performance
- only free/open-source compatibility components
- eventual packaging as a self-contained macOS `.app`

## Target Architecture

```text
AoE2DE / Steam (x86-64 / eventual i386 Windows)
            |
            v
      Wine ARM64EC / WoW64
            |
            +-- x86/x86-64 CPU code --> FEX --> ARM64
            |
            +-- Direct3D 11 --> DXMT --> Metal
                                      |
                                      v
                                  Apple GPU
```

## Core Components

| Component | Role |
|---|---|
| Wine ARM64 / ARM64EC / WoW64 | Windows API and ABI compatibility |
| FEX | x86/x86-64 -> ARM64 CPU translation |
| DXMT | Direct3D 11 -> Metal translation |
| Steam for Windows | Required launcher/account/multiplayer environment |
| macOS 26.5+ | Provides required cross-architecture process features |

## Main Risk

The difficult part is **not AoE2DE or D3D11**.

The main engineering risk is:

> reliable open-source **FEX <-> ARM64EC Wine integration on macOS**, especially across Steam's mixed helper processes.

Polished packaging should come only after this works reliably. A minimal loader app bundle and valid provisioning are early runtime requirements.

## Selected Signing Strategy

Use a **free Apple developer account with SIP and AMFI enabled**. Validate entitlement access before investing heavily in the Wine/FEX port.

Two related restricted entitlements exist:

- `com.apple.developer.cross-architecture-support`: reported as available to paid developer accounts.
- `com.apple.developer.cross-architecture-support-unmanaged`: reported as available to free developer accounts, but account access and the workflow still need validation.

Adding either entitlement to a plist and ad-hoc signing is not sufficient under normal enforcement. The signature must match authorization from a provisioning profile.

If free-account provisioning fails, record the specific failure and investigate it. Do not automatically switch to disabled SIP or relaxed AMFI. Security-relaxed bring-up is not the selected implementation path.

## Initial Inspection

Observed on 2026-10-02:

- The repository contained a short README and this plan; no runtime implementation was present.
- The development Mac runs macOS 26.6.2 on ARM64, with the 26.5 SDK and SIP enabled.
- The active developer directory is `/Library/Developer/CommandLineTools`; `xcodebuild` cannot run with that selection. Check for a full Xcode installation during setup.
- The August Wine announcement confirms the platform facilities and both entitlement names.
- The September follow-up records unresolved free-account access questions at that time.
- MR11638 was inaccessible behind a bot challenge. Its current status and exact changes remain to be inspected.

These observations do not establish that the runtime works, that provisioning is available to this account, or that AMFI enforcement has been independently verified.

## Phase 0 — Platform and Source Prerequisites

### 0.1 — Validate Free-Account Provisioning

1. Create an App ID for the Wine loader.
2. Attempt to enable the Cross-architecture Compatibility Framework capability.
3. Register this Mac using its provisioning UDID.
4. Obtain a development provisioning profile authorizing `com.apple.developer.cross-architecture-support-unmanaged`.
5. Inspect the profile's entitlement authorization, application identifier, signing certificate, device eligibility, and expiration.

**Gate:** obtain an authorized profile and matching signing identity. Treat inability to obtain them as a blocker to investigate before major porting work.

### 0.2 — Establish Reproducible Toolchains

- Check/select an appropriate full Xcode installation.
- Verify SDK declarations and linker support for the cross-architecture APIs.
- Select an ARM64-hosted LLVM/MinGW toolchain with ARM64EC PE support.
- Compile small ARM64 and ARM64EC probes.
- Record versions and ensure required build executables run natively.

### 0.3 — Audit and Pin Upstream Sources

Use Wine 11.18 as the proposed baseline, subject to confirming the tag and relevant fixes. Compare that baseline, current master, MR11638, and any subsequently published official macOS ARM64 work.

Classify each relevant change:

| Classification | Action |
|---|---|
| Already upstream | Use the upstream implementation |
| Still required | Carry a focused topic patch |
| Superseded by the macOS APIs | Implement against the supported API |
| Temporary workaround | Document and exclude from the intended runtime |

Perform equivalent source audits for FEX and DXMT, then record exact commits. Treat experimental Darwin forks as reference material until their relevant paths have been verified.

**Deliverables:** source manifest, Wine patch matrix, toolchain requirements, and identified FEX/DXMT porting gaps.

## Milestones

### M0 — Provisioned Native ARM64 Wine

Introduce a minimal loader bundle early:

```text
WineLoader.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── <actual Wine loader/launcher>
    └── embedded.provisionprofile
```

This is runtime infrastructure; the polished launcher remains M6. Determine the actual executable arrangement from the pinned Wine implementation.

Implement or adopt:

- **Address layout:** x86-compatible Mach-O layout and low-address mappings, using the supported linker facility such as `-Wl,-x86_64_layout_emulation`.
- **4 KiB pages:** process creation using `posix_spawnattr_set_4k_page_size_np()` where Windows execution requires it.
- **x18:** custom-x18 ABI transitions at the appropriate Windows/macOS boundaries, following the SDK contract.
- **TSO:** per-thread `thread_set_x86_64_compat()` setup where translated x86 execution requires it; new threads do not inherit the state.
- **Signing:** valid provisioning and signatures for each relevant executable.

Start with the conceptual Wine architecture configuration:

```text
--enable-archs=aarch64,arm64ec
```

This does not imply an unpatched upstream tree is a working macOS runtime.

**Acceptance criteria:**

- A native ARM64 Windows console probe runs through Wine.
- The process reports the expected page size and establishes required mappings.
- Windows calls, native callbacks, thread creation, and exception handling pass focused probes.
- Required host processes are ARM64 and run with SIP/AMFI enforcement enabled.

A loader printing its version is insufficient evidence that the runtime works.

### M1 — x86-64 Execution

Determine the smallest Darwin adaptation needed by FEX's Wine emulation backend. Audit memory/JIT handling, exceptions, thread state, TLS, synchronization, and native unixlib integration.

Build and connect the x64 emulation component through Wine's supported interface. Verify exact DLL naming and installation rules against the pinned revisions, including the relationship between `libarm64ecfex.dll` and Wine's `xtajit64.dll` interface.

Use a source-controlled, explicitly x86-64 console executable before Notepad.

```text
ARM64 Mach-O Wine
  -> ARM64EC dispatch
  -> FEX
  -> hello-x64.exe
```

**Acceptance criteria:**

- Correct output and exit status.
- Evidence that the PE is x86-64 and FEX actually executes it.
- Repeated successful launches.
- Focused coverage for threads, exceptions, virtual-memory protection changes, and host callbacks.
- No translated Mach-O processes in the runtime process tree.

Keep Steam, i386, and graphics outside M1.

### M1.5 — Complete Provisioned Runtime

Because development starts with SIP enabled, this is an integration and reproducibility gate rather than a transition from bypass mode.

Validate:

- execution from the intended bundle;
- profile authorization and signature consistency;
- child-process launch paths;
- fresh threads receiving required compatibility state;
- operation from a clean Wine prefix;
- reproducible setup using the documented free-account workflow.

**Acceptance:** the complete M1 runtime works under normal SIP/AMFI enforcement, with a documented provisioning process.

A development-profile build working on a registered Mac does not establish that another user can copy and run it. Record signing, device-registration, renewal, and distribution constraints here. They may affect the final “copy one app” goal.

### M2 — Mixed Architecture Support and Steam

Determine which architectures the selected Steam build requires. Add i386 support and FEX's WoW64 backend as needed, validating them with a small 32-bit probe before debugging Steam. Verify the expanded Wine architecture configuration against the pinned sources.

Install and launch Windows Steam, then validate:

- installation and updates
- login and session persistence
- Store/Library UI
- downloads
- Steam helper-process startup and restart
- launching a test application

**Success:** Steam operates reliably without Rosetta.

### M3 — D3D11 Smoke Test and AoE2DE Launch

Move minimal graphics integration ahead of the main-menu gate:

1. Build the required DXMT PE and native components for this runtime.
2. Validate the ARM64EC/native ABI boundaries.
3. Run a small D3D11 device-creation and rendering test.
4. Install the Windows Steam build of AoE2DE and reach the main menu.

**Success:** verified Metal-backed D3D11 rendering and a stable game menu.

### M4 — Gameplay and Performance

Validate a representative single-player scenario using ARM64EC-compatible DXMT.

Target path:

```text
AoE2DE D3D11 -> DXMT -> Metal -> Apple GPU
```

Validate:

- rendering
- fullscreen/windowing
- input
- audio
- acceptable frame pacing
- save/load
- extended-session stability
- CPU translation and graphics bottlenecks

Define the performance target for the actual Mac, resolution, settings, and scenario before calling it “native-feeling.”

**Success:** normal gameplay is practical.

### M5 — Multiplayer

Join a lobby with Windows players and complete a real match.

Validate:

- Steam networking
- AoE services
- matchmaking/lobbies
- game-version compatibility
- simulation synchronization and desyncs
- stability over a full session
- repeated sessions

**Success:** repeatable completed matches with Windows players on matching game versions.

### M6 — Packaging

Only after M0-M5, including M1.5, succeed:

- create a self-contained `.app`
- bundle redistributable Wine, FEX, DXMT components, launch scripts, configuration, and license notices
- keep the Wine prefix and writable data isolated
- provide first-run Steam installation and game launch
- implement the signing/provisioning distribution model established earlier
- launch Steam directly into AoE2DE where practical
- validate installation on another supported Mac
- repeat the no-Rosetta audit

## Proposed Repository Layout

```text
sources.lock
patches/
    wine/
    fex/
    dxmt/
scripts/
    check-host.sh
    build-wine.sh
    build-fex.sh
    build-dxmt.sh
    sign-loader.sh
    verify-no-rosetta.sh
bundle/
    WineLoader.app/
        Contents/Info.plist
tests/
    hello-arm64/
    hello-x64/
    hello-x86/
    runtime/
    d3d11-smoke/
docs/
    upstream-audit.md
    provisioning.md
    milestones.md
```

Keep source checkouts, build products, prefixes, and machine-specific provisioning material outside tracked source files. Store test source and build instructions rather than only prebuilt executables.

## First Implementation Work Package

End the first work package with:

1. A verified free-account entitlement/provisioning result.
2. A native toolchain capability report.
3. Pinned upstream revisions and a classified Wine patch matrix.
4. A minimal signed platform probe demonstrating the required macOS facilities.

The earliest blockers to expose are entitlement availability and missing Darwin runtime support, before Steam or game debugging begins.

## Development Rule

Do **not** optimize packaging or UI before multiplayer works.

Work in this order:

```text
free-account provisioning and toolchain/source audit
    -> provisioned native Wine
    -> FEX
    -> trivial x86-64 executable
    -> complete provisioning/reproducibility gate
    -> mixed-architecture Steam
    -> D3D11 smoke test / AoE2DE menu
    -> gameplay and performance
    -> Windows multiplayer
    -> polished .app
```

## Definition of Done

The project is complete when a user can:

1. install/copy one macOS application bundle,
2. launch it on Apple Silicon without Rosetta,
3. sign in to Windows Steam,
4. launch the Windows build of AoE2DE,
5. play smoothly through Metal,
6. join and complete multiplayer games with Windows friends.

## Guiding Principle

Prefer **native ARM64 host components** and translate only what must remain x86/x86-64.

```text
x86 Windows application code -> FEX
Windows APIs                -> Wine
D3D11                       -> DXMT
GPU execution               -> native Metal / Apple GPU
```

## References and Verification Status

- [Wine on ARM64 macOS, Brendan Shanks, August 7, 2026](https://list.winehq.org/hyperkitty/list/wine-devel%40list.winehq.org/message/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/) — inspected; describes x18, 4 KiB pages, address layout, TSO, and entitlement requirements.
- [Free-account follow-up, September 9, 2026](https://list.winehq.org/hyperkitty/list/wine-devel%40list.winehq.org/message/EYMEAE4QQE2CR4OBITUENL3LB67ECDLU/) — inspected; capability access and documentation were still unresolved for the reporting user.
- [Apple TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles) — authoritative provisioning reference; the text fetch returned only the page title, so inspect the full document during implementation.
- [Wine MR11638](https://gitlab.winehq.org/wine/wine/-/merge_requests/11638) — pending inspection; access was blocked by a bot challenge. Do not treat the patch classification as completed.
- [Experimental FEX macOS fork](https://github.com/Jpkovas/FEX_MacOs) — candidate reference for the source audit; suitability has not been verified.
