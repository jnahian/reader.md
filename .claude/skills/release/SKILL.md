---
name: release
description: Cut a Reader.md release — bump versions, update the changelog, build the .app, and publish the Sparkle update. Use when the user wants to release, ship a new version, publish an update, or cut a build of Reader.md.
---

# Release Reader.md

A release touches version numbers in three files, the changelog, and a tag that
must point at the committed bump. Miss any one and the DMG, the appcast, and the
source drift apart. Work the checklist top to bottom — **create one todo per
numbered step.**

## 1. Decide the version

- **Display version** (`CFBundleShortVersionString`): semver, e.g. `1.5.0`. This
  is the only version you choose.
- **Build number** (`CFBundleVersion`): derived automatically from the build
  time (`date +%Y%m%d%H%M`) in `make-app.sh` — nothing to bump. It's what Sparkle
  compares, and being time-based it's always monotonic.

## 2. Bump the display version in `make-app.sh`

Edit the one line (~61):

```
<key>CFBundleShortVersionString</key><string>NEW_DISPLAY</string>
```

Leave `CFBundleVersion` alone — it's `${BUILD_NUMBER}` and set at build time.

## 3. Sync the About fallback in `Sources/ReaderMd/ReaderMdApp.swift`

`showAboutPanel()` (~line 112) hard-codes the display version as the `swift run`
fallback. Keep it equal to the new display version:

```
let version = info?["CFBundleShortVersionString"] as? String ?? "NEW_DISPLAY"
```

Leave `build ... ?? "dev"` alone — "dev" is intentional for `swift run`.

## 4. Update `Sources/ReaderMd/Resources/docs/CHANGELOG.md`

The changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
with semver versions. It is read by users, not machines: Sparkle shows the
section in its update prompt and the app opens it as What's New after updating.

- Rename `## [Unreleased]` to `## [NEW_DISPLAY] - YYYY-MM-DD` — bracketed
  version, ISO date, today's.
- Group the entries under the standard headings, in this order, omitting any
  that are empty:

  ```markdown
  ## [Unreleased]

  ## [1.12.0] - 2026-07-21

  ### Added
  - **A lead-in in bold** — then what it does, in a sentence a user recognizes.

  ### Changed
  - **Quick Open matches like the sidebar** — typing finds the same files the
    sidebar filter finds, instead of a looser fuzzy match.

  ### Fixed
  - **Quick Open's arrow keys** — up and down now move through the results
    you're looking at. They previously walked a stale list.
  ```

  `Added` / `Changed` / `Deprecated` / `Removed` / `Fixed` / `Security` — those
  six, spelled that way. Anything that isn't new and isn't a bug fix is
  `Changed`.
- Write for the person who installed the app, not the person who wrote the
  patch: name the behavior they'll notice, not the type or function. Keep the
  bold lead-in — the app renders these as markdown.
- **If the Unreleased section is empty, stop** and ask the user what changed —
  a release with no notes means changelog entries were never written during
  development. Fill them before continuing.
- Leave a bare `## [Unreleased]` heading at the top for the next change.
- Entries older than the switch to this format are prose bullets under a
  `## X.Y.Z — date` heading. Leave them; `release.sh` parses both heading styles.

## 5. Verify versions agree (before building)

```
grep -rn "NEW_DISPLAY" make-app.sh Sources/ReaderMd/ReaderMdApp.swift Sources/ReaderMd/Resources/docs/CHANGELOG.md
```

All three files should show `NEW_DISPLAY`. Confirm the build number increased.

## 6. Run the tests

```
swift test
```

All tests must pass before you commit the bump. `swift test` covers more than
`fuzzyScore` — the `ReadingTheme` resolver, URL routing, stdin temp handling,
etc. — so `swift build` succeeding is **not** enough. In particular, changing an
enum (e.g. removing a reading theme) breaks the assertions that pin its
`allCases` and name resolution; fix those tests here, not after the release.

## 7. Commit and push the bump — before releasing

`gh release create` tags the latest **pushed** commit. If the bump isn't
committed and pushed, the tag and the DMG's source won't match.

```
git add make-app.sh Sources/ReaderMd/ReaderMdApp.swift Sources/ReaderMd/Resources/docs/CHANGELOG.md
git commit -m "chore: release vNEW_DISPLAY (build NEW_BUILD)"
git push
```

## 8. Build the app

```
./make-app.sh
```

Sanity-check the versions baked into the bundle:

```
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "build/Reader.md.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "build/Reader.md.app/Contents/Info.plist"
```

Optional smoke test: `open build/Reader.md.app`, confirm About shows the new
version and **Help → Release Notes** shows the new changelog entry.

## 9. Publish

```
./release.sh
```

`release.sh` re-checks that the time-based `CFBundleVersion` exceeds the
published build (it always will, short of clock skew) and refuses otherwise. It
signs the DMG, generates `appcast.xml`, and uploads both to the `vNEW_DISPLAY`
GitHub release. It then rewrites `Casks/reader-md.rb` with the new version and
the uploaded DMG's sha256 and commits that (`chore: update Homebrew cask …`), so
the `brew install --cask` tap tracks the release automatically — nothing to bump
by hand.

## 10. Confirm

```
gh release view "vNEW_DISPLAY" --repo jnahian/reader.md
```

The release must be the newest non-prerelease (so
`releases/latest/download/appcast.xml` resolves) and carry both the `.dmg` and
`appcast.xml` assets. Updates reach Apple-silicon Macs only (arm64 binary).

## 11. Sync the web changelog

The marketing site keeps its own hand-maintained copy of the release notes in
`web/src/data/changelog.ts` — nothing in `release.sh` touches it. Mirror the new
`## NEW_DISPLAY` section from `CHANGELOG.md` into it:

- Add a `Release` entry at the top with `version`, `date` ("Mon D, YYYY"), and
  the items grouped into `ADDED` / `IMPROVED` / `FIXED` (items are HTML strings
  with a bold `<strong>` lead-in). The site's buckets are narrower than Keep a
  Changelog's headings: `Added` → `ADDED`, `Fixed` → `FIXED`, everything else
  (`Changed`, `Removed`, `Deprecated`, `Security`) → `IMPROVED`.
- Move the `badge: "LATEST"` from the previous release onto the new one.
- Deploying the site is a separate step — see `web/DEPLOYMENT.md` (`wrangler
  pages deploy`); it is not part of the app release.

## What goes missing if you skip a step

| Skipped | Symptom |
| --- | --- |
| `swift test` not run (only `swift build`) | Red tests land on `main`; a stale enum assertion (e.g. removed theme) slips through |
| About fallback not synced | `swift run` shows the old version |
| Changelog `Unreleased` not renamed | Release Notes still say "Unreleased" |
| Bump not committed/pushed before release | Tag points at old source; DMG ≠ tag |
| `release.sh` cask commit not pushed | `brew install --cask` serves the previous version |
| `web/src/data/changelog.ts` not synced | The marketing site's changelog lags the release |
