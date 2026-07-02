# Releasing Signal

Releases are automated with [changesets](https://github.com/changesets/changesets)
and GitHub Actions. Every release produces:

- a **git tag** `vX.Y.Z` and a **GitHub Release** with changelog notes,
- a signed, notarized, stapled **DMG** attached to the release
  (plus an unversioned `Signal.dmg` copy so
  `https://github.com/thiagobrez/Signal/releases/latest/download/Signal.dmg`
  always points at the latest version),
- an **App Store Connect upload** of the same archive (TestFlight distribution
  and App Review submission stay manual in ASC).

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
