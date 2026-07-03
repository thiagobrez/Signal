# Releasing Signal

Releases are automated with [changesets](https://github.com/changesets/changesets)
and GitHub Actions. Every release produces:

- a **git tag** `vX.Y.Z` and a **GitHub Release** with changelog notes,
- a signed, notarized, stapled **DMG** attached to the release
  (plus an unversioned `Signal.dmg` copy so
  `https://github.com/thiagobrez/Signal/releases/latest/download/Signal.dmg`
  always points at the latest version),
- an updated **Sparkle appcast** (`docs/appcast.xml`, committed to `master`
  and served by GitHub Pages at
  `https://thiagobrez.github.io/Signal/appcast.xml`) so existing
  direct-download installs auto-update,
- an **App Store Connect upload** (TestFlight distribution and App Review
  submission stay manual in ASC).

Two separate archives are built: the `Signal` scheme (direct download, links
Sparkle) and the `SignalAppStore` scheme (no Sparkle — the App Store rejects
apps that embed their own updater; MAS users update through the App Store).

## Day-to-day flow

1. In any PR with user-visible changes, run `npx changeset`, pick
   patch/minor/major, write a short summary, and commit the generated
   `.changeset/*.md` file.
2. Merge to `master`. The **Release** workflow opens/updates a
   `chore: release` PR ("Version Packages") that bumps `package.json`,
   `project.yml` (`MARKETING_VERSION`, via `scripts/sync-version.sh`) and
   `CHANGELOG.md`.
3. Merge that PR when you want to cut the release. The workflow tags, creates
   the GitHub Release, and the **Build & Publish** workflow (same run) builds,
   notarizes, attaches the DMG and uploads to App Store Connect.

Commits without changesets never trigger a release.

## Version / build number rules

- `package.json` is the **source of truth** for the marketing version. Never
  hand-edit `MARKETING_VERSION` in `project.yml` — `scripts/sync-version.sh`
  overwrites it.
- The build number (`CURRENT_PROJECT_VERSION`) is injected at build time as
  `git rev-list --count HEAD` (override with the `build-number` input when
  re-dispatching, e.g. after a failed ASC upload of the same version).
- The committed `Signal.xcodeproj` may lag behind `project.yml`; CI always runs
  `xcodegen generate` first. Run it locally too before archiving by hand.

## Automatic updates (Sparkle)

Direct-download builds self-update via [Sparkle](https://sparkle-project.org):
the app polls `https://thiagobrez.github.io/Signal/appcast.xml`, which the
**Build & Publish** workflow regenerates and commits to `docs/` on `master`
after notarizing each release DMG. Every appcast item is EdDSA-signed.

One-time setup (already done if `SUPublicEDKey` in `Signal/Info.plist` holds a
real key):

1. Download the Sparkle distribution matching `SPARKLE_TOOLS_VERSION` in
   `release-build.yml` and run `./bin/generate_keys`. Paste the printed
   **public** key into `Signal/Info.plist` → `SUPublicEDKey` (safe to commit).
2. Export the private key with `./bin/generate_keys -x /tmp/sparkle_key`, add
   the file's contents as the `SPARKLE_ED_PRIVATE_KEY` repo secret, then
   delete the file. Losing this key means shipped apps reject future updates,
   so keep the Keychain copy backed up.

Notes:

- Keep `SPARKLE_TOOLS_VERSION` in `release-build.yml` in sync with the Sparkle
  package version in `project.yml`.
- Users on versions released before Sparkle was added must re-download the DMG
  once; auto-update works from then on.

## Required repo secrets

`APPLE_TEAM_ID`, `DEVELOPER_ID_APPLICATION_P12_BASE64`,
`DEVELOPER_ID_APPLICATION_P12_PASSWORD`, `APP_STORE_CONNECT_API_KEY_ID`,
`APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8_BASE64`,
`TELEMETRYDECK_APP_ID`, `SPARKLE_ED_PRIVATE_KEY`.
