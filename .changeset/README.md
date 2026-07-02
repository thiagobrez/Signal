# Changesets

This app is versioned with [changesets](https://github.com/changesets/changesets),
even though it's a Swift app — changesets only manages `package.json`'s version
and `CHANGELOG.md`; `scripts/sync-version.sh` propagates the version into
`project.yml` (`MARKETING_VERSION`).

When a change is worth mentioning in the release notes, add a changeset in the
same PR:

```sh
npx changeset
```

Pick patch / minor / major and write a short user-facing summary. Merging to
`master` updates the "Version Packages" PR; merging *that* PR cuts the release
(tag + GitHub Release with notarized DMG + App Store Connect upload).

See RELEASING.md at the repo root for the full picture.
