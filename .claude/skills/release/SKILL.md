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

- Rename `## Unreleased` to `## NEW_DISPLAY — YYYY-MM-DD` (today's date).
- **If the Unreleased section is empty, stop** and ask the user what changed —
  a release with no notes means changelog entries were never written during
  development. Fill them before continuing.
- Do not leave an empty `## Unreleased` behind; add it again when the next
  change lands.

## 5. Verify versions agree (before building)

```
grep -rn "NEW_DISPLAY" make-app.sh Sources/ReaderMd/ReaderMdApp.swift Sources/ReaderMd/Resources/docs/CHANGELOG.md
```

All three files should show `NEW_DISPLAY`. Confirm the build number increased.

## 6. Commit and push the bump — before releasing

`gh release create` tags the latest **pushed** commit. If the bump isn't
committed and pushed, the tag and the DMG's source won't match.

```
git add make-app.sh Sources/ReaderMd/ReaderMdApp.swift Sources/ReaderMd/Resources/docs/CHANGELOG.md
git commit -m "chore: release vNEW_DISPLAY (build NEW_BUILD)"
git push
```

## 7. Build the app

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

## 8. Publish

```
./release.sh
```

`release.sh` re-checks that the time-based `CFBundleVersion` exceeds the
published build (it always will, short of clock skew) and refuses otherwise. It
signs the DMG, generates `appcast.xml`, and uploads both to the `vNEW_DISPLAY`
GitHub release.

## 9. Confirm

```
gh release view "vNEW_DISPLAY" --repo jnahian/reader.md
```

The release must be the newest non-prerelease (so
`releases/latest/download/appcast.xml` resolves) and carry both the `.dmg` and
`appcast.xml` assets. Updates reach Apple-silicon Macs only (arm64 binary).

## What goes missing if you skip a step

| Skipped | Symptom |
| --- | --- |
| About fallback not synced | `swift run` shows the old version |
| Changelog `Unreleased` not renamed | Release Notes still say "Unreleased" |
| Bump not committed/pushed before release | Tag points at old source; DMG ≠ tag |
