#!/usr/bin/env bash
# Release both apps at the same version: bump once, then publish the Mac build to GitHub
# Releases (release-mac.sh) and upload the iOS build to TestFlight (testflight.sh).
#
#   ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/release.sh
#
# The individual scripts can still be run alone; they only bump when the version is not
# already current, so `VERSION=x.y.z scripts/testflight.sh` after a Mac release also works.
# Set MAC=0 or IOS=0 to skip one side.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID and ASC_ISSUER_ID (needed for notarization and the TestFlight upload)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"

source scripts/bump-version.sh
export VERSION

if [ "${MAC:-1}" = "1" ]; then
  echo "########## macOS $VERSION"
  scripts/release-mac.sh
fi
if [ "${IOS:-1}" = "1" ]; then
  echo "########## iOS $VERSION"
  scripts/testflight.sh
fi
echo "==> Released $VERSION for$([ "${MAC:-1}" = "1" ] && echo " macOS")$([ "${IOS:-1}" = "1" ] && echo " iOS")."
