#!/usr/bin/env bash
# Archive a Release build and upload it to App Store Connect (TestFlight).
#
# Requires an App Store Connect API key (Team key, App Manager role):
#   ASC_KEY_ID      e.g. ABC123DEF4
#   ASC_ISSUER_ID   UUID from the App Store Connect API page
#   ASC_KEY_PATH    path to AuthKey_<KEY_ID>.p8
#                   (defaults to ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8)
#
# Optional:
#   BUILD_NUMBER    overrides CURRENT_PROJECT_VERSION (defaults to the UTC timestamp,
#                   which is always increasing so uploads never collide)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[ -f "$ASC_KEY_PATH" ] || { echo "missing API key at $ASC_KEY_PATH" >&2; exit 1; }

BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
OUT="build/testflight"
ARCHIVE="$OUT/PhotoSwipe.xcarchive"
rm -rf "$OUT" && mkdir -p "$OUT"

xcbeautify_or_tail() {
  if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else grep -E "error|warning: |ARCHIVE|EXPORT|Upload" || true; fi
}

AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "==> Archiving build $BUILD_NUMBER"
xcodebuild -project PhotoSwipe.xcodeproj -scheme PhotoSwipe -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration "${AUTH[@]}" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive | xcbeautify_or_tail

echo "==> Uploading to App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -allowProvisioningUpdates "${AUTH[@]}" | xcbeautify_or_tail

echo "==> Uploaded build $BUILD_NUMBER. Processing takes 5-15 minutes before it appears in TestFlight."
