#!/usr/bin/env bash
# Archive a Release build and upload it to App Store Connect (TestFlight).
#
# Authentication, in order of preference:
#   1. App Store Connect API key (unattended):
#        ASC_KEY_ID      e.g. ABC123DEF4
#        ASC_ISSUER_ID   UUID from the App Store Connect API page
#        ASC_KEY_PATH    path to AuthKey_<KEY_ID>.p8
#                        (defaults to ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8)
#   2. Otherwise the Apple ID signed in to Xcode (Settings > Accounts) is used via
#      -allowProvisioningUpdates. If Xcode's session has expired, sign in there again.
#
# Versioning: every run bumps the patch component of MARKETING_VERSION in project.yml
# (1.0 -> 1.0.1 -> 1.0.2 ...), regenerates the .xcodeproj, and commits + tags the bump
# (v1.0.1) so the next run continues from there. The commit is NOT pushed; push when
# convenient. Requires a clean working tree so the bump commit contains only the bump.
#
# Optional:
#   VERSION         sets MARKETING_VERSION explicitly (e.g. 1.1 or 2.0.0) instead of bumping
#   BUILD_NUMBER    overrides CURRENT_PROJECT_VERSION (defaults to the UTC timestamp,
#                   which is always increasing so uploads never collide)
#   ALLOW_DIRTY=1   bump even with uncommitted changes (they stay out of the bump commit)
set -euo pipefail
cd "$(dirname "$0")/.."

# ---- Version bump (shared) ---------------------------------------------------
source scripts/bump-version.sh

AUTH=()
if [ -n "${ASC_KEY_ID:-}" ]; then
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID when ASC_KEY_ID is set}"
  ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  [ -f "$ASC_KEY_PATH" ] || { echo "missing API key at $ASC_KEY_PATH" >&2; exit 1; }
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
else
  echo "==> No ASC_KEY_ID set; using the Apple ID signed in to Xcode"
fi

BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
OUT="build/testflight"
ARCHIVE="$OUT/PhotoSwipe.xcarchive"
rm -rf "$OUT" && mkdir -p "$OUT"

xcbeautify_or_tail() {
  if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else grep -E "error|warning: |ARCHIVE|EXPORT|Upload" || true; fi
}

echo "==> Archiving $VERSION ($BUILD_NUMBER)"
xcodebuild -project PhotoSwipe.xcodeproj -scheme PhotoSwipe -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration ${AUTH[@]+"${AUTH[@]}"} \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive | xcbeautify_or_tail

echo "==> Uploading to App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} | xcbeautify_or_tail

echo "==> Uploaded $VERSION ($BUILD_NUMBER). Processing takes 5-15 minutes before it appears in TestFlight."
echo "    Version bump committed and tagged v$VERSION; run 'git push --follow-tags' to publish it."
