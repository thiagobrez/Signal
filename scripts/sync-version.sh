#!/usr/bin/env bash
# Propagates package.json's version (changesets' source of truth) into
# project.yml MARKETING_VERSION. Runs as part of `npm run version`, so the
# changesets "Version Packages" PR carries the project.yml bump alongside
# package.json and CHANGELOG.md.
#
# Do not hand-edit MARKETING_VERSION in project.yml — it gets overwritten here.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(node -p "require('./package.json').version")

# sed instead of a YAML parser: the MARKETING_VERSION line format is stable and
# this keeps the script dependency-free. -i.bak + rm is portable GNU/BSD sed.
sed -i.bak -E "s/^([[:space:]]*MARKETING_VERSION:).*/\1 \"$VERSION\"/" project.yml
rm project.yml.bak

grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml \
  || { echo "sync-version: failed to update project.yml" >&2; exit 1; }

echo "sync-version: project.yml MARKETING_VERSION -> $VERSION"

# Keep the committed xcodeproj in sync when running locally; CI regenerates
# unconditionally before building, so this is best-effort.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi
