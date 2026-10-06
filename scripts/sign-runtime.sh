#!/usr/bin/env bash
# Sign only the known native Wine outputs of one profile, after a successful build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${AOE2_WORK_ROOT:-$HOME/aoe2-poc-work}"
BUILD="$WORK/build/wine-${AOE2_WINE_PROFILE:-m0}"
for path in "$BUILD/loader/wine" "$BUILD/server/wineserver" "$BUILD/dlls/ntdll/ntdll.so"; do
    test -f "$path" || { echo "Missing build output: $path" >&2; exit 1; }
    file "$path" | /usr/bin/grep -q 'arm64' || { echo "Not ARM64: $path" >&2; exit 1; }
done
# Only the main Wine executable owns the cross-architecture process facilities.
codesign --force --sign - --entitlements "$ROOT/tests/platform/entitlements.plist" "$BUILD/loader/wine"
codesign --force --sign - "$BUILD/server/wineserver"
# All native Wine libraries must have valid signatures after relinking.
while IFS= read -r -d '' path; do
    codesign --force --sign - "$path"
    codesign --verify --strict "$path"
done < <(find "$BUILD/dlls" -name '*.so' -type f -print0)
codesign --verify --strict "$BUILD/loader/wine"
codesign --verify --strict "$BUILD/server/wineserver"
codesign --display --entitlements :- "$BUILD/loader/wine" > "$BUILD/signature-entitlements.plist" 2> "$BUILD/signature-inspection.log"
echo "Signatures verified: $BUILD"
