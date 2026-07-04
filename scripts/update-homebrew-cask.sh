#!/usr/bin/env bash
# Regenerates Casks/signal.rb in a checkout of thiagobrez/homebrew-tap for a
# given release. Full-file rewrite from the template below — keeping the
# template here means cask changes are reviewed in this repo, and the
# Build & Publish workflow (which commits and pushes the tap) stays a dumb
# executor.
#
# Usage: update-homebrew-cask.sh <version> <dmg-sha256> <tap-checkout-dir>
set -euo pipefail

USAGE="usage: update-homebrew-cask.sh <version> <dmg-sha256> <tap-checkout-dir>"
VERSION="${1:?$USAGE}"
SHA256="${2:?$USAGE}"
TAP_DIR="${3:?$USAGE}"

mkdir -p "$TAP_DIR/Casks"

# The DMG is the same signed + notarized artifact attached to the GitHub
# Release; the cask just pins its hash. auto_updates: installs self-update via
# Sparkle, so `brew upgrade` skips them unless --greedy.
cat > "$TAP_DIR/Casks/signal.rb" <<EOF
cask "signal" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/thiagobrez/Signal/releases/download/v#{version}/Signal-#{version}.dmg",
      verified: "github.com/thiagobrez/Signal/"
  name "Signal"
  desc "Daily planner for focusing on three things a day"
  homepage "https://thiagobrez.github.io/Signal/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Signal.app"

  zap trash: "~/Library/Containers/ski.brezin.signal"
end
EOF

echo "update-homebrew-cask: wrote $TAP_DIR/Casks/signal.rb (version $VERSION)"
