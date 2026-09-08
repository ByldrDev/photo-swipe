#!/usr/bin/env bash
# Build the macOS app and publish it as a GitHub release: a .dmg (drag to Applications) and a
# .zip attached to the tag. Re-running for an existing version replaces the assets and notes.
#
# Signing, decided by what is in the login keychain:
#   - "Developer ID Application" certificate present: the app is signed with it, notarized
#     through the App Store Connect API key (ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH, same
#     as testflight.sh) and stapled, so it opens with no Gatekeeper warning.
#   - Otherwise it is ad-hoc signed ("sign to run locally"). It still runs, but macOS makes
#     downloaders confirm once: right-click → Open, or System Settings → Privacy & Security →
#     Open Anyway. The release notes say so.
#
# Every run bumps the patch version (scripts/bump-version.sh), pushes the commit + tag, and
# creates the release from that tag. Requires the gh CLI, logged in.
#
# Optional: VERSION, BUILD_NUMBER, ALLOW_DIRTY=1 (see bump-version.sh), DRAFT=1 to create a
# draft release instead of publishing immediately.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v gh >/dev/null 2>&1 || { echo "gh CLI is required (brew install gh; gh auth login)" >&2; exit 1; }

source scripts/bump-version.sh

BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
OUT="build/mac-release"
rm -rf "$OUT" && mkdir -p "$OUT"

xcbeautify_or_tail() {
  if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else grep -E "error|warning: |BUILD" || true; fi
}

# `|| true`: under pipefail a no-match grep would otherwise abort the script.
DEVID="$(security find-identity -v -p codesigning 2>/dev/null | { grep -o '"Developer ID Application: [^"]*"' || true; } | head -1 | tr -d '"')"
if [ -n "$DEVID" ]; then
  echo "==> Building $VERSION ($BUILD_NUMBER) signed with: $DEVID"
  SIGN=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$DEVID" OTHER_CODE_SIGN_FLAGS=--timestamp PROVISIONING_PROFILE_SPECIFIER=)
else
  echo "==> No Developer ID Application certificate in the keychain; building $VERSION ($BUILD_NUMBER) ad-hoc signed"
  SIGN=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
fi

xcodebuild -project PhotoSwipe.xcodeproj -scheme PhotoSwipeMac -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$OUT/derived" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${SIGN[@]}" \
  build | xcbeautify_or_tail

APP="$OUT/derived/Build/Products/Release/PhotoSwipe.app"
ZIP="$OUT/PhotoSwipe-$VERSION-macOS.zip"
[ -d "$APP" ] || { echo "build did not produce $APP" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

if [ -n "$DEVID" ]; then
  : "${ASC_KEY_ID:?set ASC_KEY_ID (and ASC_ISSUER_ID) to notarize}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID when ASC_KEY_ID is set}"
  ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  echo "==> Notarizing"
  ditto -c -k --keepParent "$APP" "$ZIP"
  RESULT="$(xcrun notarytool submit "$ZIP" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait 2>&1 | tee /dev/stderr)"
  echo "$RESULT" | grep -q "status: Accepted" || { echo "notarization failed; see 'xcrun notarytool log <id>'" >&2; exit 1; }
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  OPEN_NOTE="Signed and notarized: double-click to open."
else
  OPEN_NOTE="This build is not notarized, so the first launch needs one extra step: right-click PhotoSwipe.app → Open, then Open again. If macOS only offers \"Move to Trash\", open System Settings → Privacy & Security and click **Open Anyway**."
fi
ditto -c -k --keepParent "$APP" "$ZIP"

# Disk image with an Applications shortcut, the conventional Mac download.
echo "==> Building disk image"
DMG="$OUT/PhotoSwipe-$VERSION-macOS.dmg"
STAGE="$OUT/dmg"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "PhotoSwipe $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
if [ -n "$DEVID" ]; then
  codesign --sign "$DEVID" --timestamp "$DMG"
  RESULT="$(xcrun notarytool submit "$DMG" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait 2>&1 | tee /dev/stderr)"
  echo "$RESULT" | grep -q "status: Accepted" || { echo "dmg notarization failed" >&2; exit 1; }
  xcrun stapler staple "$DMG"
fi

echo "==> Pushing v$VERSION"
git push --follow-tags

NOTES="$(cat <<EOF
PhotoSwipe for macOS. Requires macOS 14 or later.

**Install:** open the .dmg, drag PhotoSwipe to Applications, launch it and allow Photos access when asked. (A .zip of the app is attached too.)

$OPEN_NOTE

**Keys:** ← delete · ↑ hide · → keep · ⌘Z undo · space play/pause · M mute · double-click zoom · esc close.
Nothing is deleted or hidden until you confirm on the Review screen; deleted photos go to Recently Deleted for 30 days.

Build $BUILD_NUMBER.
EOF
)"
FLAGS=()
[ "${DRAFT:-}" = "1" ] && FLAGS+=(--draft)
if gh release view "v$VERSION" >/dev/null 2>&1; then
  echo "==> Updating existing GitHub release v$VERSION"
  gh release upload "v$VERSION" "$DMG" "$ZIP" --clobber
  gh release edit "v$VERSION" --title "PhotoSwipe $VERSION" --notes "$NOTES"
  gh release view "v$VERSION" --json url -q .url
else
  echo "==> Creating GitHub release v$VERSION"
  gh release create "v$VERSION" "$DMG" "$ZIP" --title "PhotoSwipe $VERSION" --notes "$NOTES" "${FLAGS[@]+"${FLAGS[@]}"}"
fi
