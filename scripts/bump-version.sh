#!/usr/bin/env bash
# Sourced by scripts/testflight.sh and scripts/release-mac.sh.
#
# Bumps the patch component of MARKETING_VERSION in project.yml (1.0 -> 1.0.1 -> 1.0.2 ...),
# regenerates the .xcodeproj, and commits + tags the bump (v1.0.1). Sets $VERSION and
# $CURRENT for the caller. Requires a clean working tree unless ALLOW_DIRTY=1; set VERSION
# to choose the version explicitly instead of bumping.
set -euo pipefail

current_version() {
  sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9.]+)"?.*/\1/p' project.yml | head -1
}

next_patch() {
  local IFS=. ; read -r major minor patch <<<"$1"
  echo "${major:-1}.${minor:-0}.$(( ${patch:-0} + 1 ))"
}

CURRENT="$(current_version)"
[ -n "$CURRENT" ] || { echo "could not read MARKETING_VERSION from project.yml" >&2; exit 1; }
VERSION="${VERSION:-$(next_patch "$CURRENT")}"

if [ "${ALLOW_DIRTY:-}" != "1" ] && [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty; commit or stash first (or ALLOW_DIRTY=1)" >&2
  exit 1
fi
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is required to regenerate the project (brew install xcodegen)" >&2; exit 1; }

if [ "$VERSION" = "$CURRENT" ]; then
  # VERSION=<current> re-runs a release for a version that was already bumped
  # (e.g. after a failed upload) without creating another commit.
  echo "==> Version $VERSION (already current, not bumping)"
else
  echo "==> Version $CURRENT -> $VERSION"
  sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION:[[:space:]]*).*/\1\"$VERSION\"/" project.yml
  xcodegen generate >/dev/null
  git add project.yml PhotoSwipe.xcodeproj/project.pbxproj
  git commit -q -m "Bump version to $VERSION"
fi
git tag -fa "v$VERSION" -m "PhotoSwipe $VERSION" >/dev/null
