# Entitlement investigation — parallel to the local POC

Updated: 2026-10-05.

The user attempted entitlement access on another OS installation; it did not work. Exact account/profile errors have not been captured here. The user is querying Apple about access and the supported workflow.

Implementation now proceeds on a temporary installation with SIP and AMFI disabled. This investigation is not an implementation gate.

Observed locally: `csrutil status` reports SIP disabled; boot arguments include `amfi_get_out_of_my_way=0x1`. These are recorded facts, not a comprehensive independent audit of AMFI enforcement.

`scripts/test-platform.sh` ad-hoc signs a real ARM64 executable with `com.apple.developer.cross-architecture-support-unmanaged` and exercises the needed APIs. All cases pass on macOS 26.6.2 (25G83), SDK 27.0. Without the entitlement in the signature, the local probe was killed at launch.

This establishes local capability use under the current configuration. It does not establish entitlement authorization, provisioning, or execution under enabled SIP/AMFI. Record Apple's response and any supported enforcement-enabled workflow here when available; do not infer account access from successful ad-hoc signing.
