---
title: Building
category: Internals
order: 31
summary: Build from source, package the .app, and cut a release.
---

# Building

For contribution setup, conventions, and the PR flow, see
[CONTRIBUTING.md](../CONTRIBUTING.md). This page covers packaging.

## Run (quick, for development)

```bash
swift run ReaderMd
```

This launches the app directly. It's an unsandboxed executable, so it can read any folder you add.

## Build a double-clickable app

```bash
./make-app.sh
open "build/Reader.md.app"
```

`make-app.sh` builds a release binary, assembles `Reader.md.app` (web/KaTeX/etc. resources copied into `Contents/Resources`), converts `AppIcon.png` to `.icns`, writes `Info.plist`, **ad-hoc code-signs the bundle**, and produces `build/Reader.md.zip` for sharing.

Because the signature is ad-hoc rather than a Developer ID, anyone you hand the
build to clears quarantine once on first launch — see
[Clearing quarantine](install.md#clearing-quarantine).

## Open in Xcode

`File → Open…` this project folder (SwiftPM package). Select the `ReaderMd` scheme and Run. Use Xcode's Archive flow for a signed, distributable build.

## Cut a release

`./release.sh` publishes a signed DMG and the Sparkle appcast. It refuses to run
if the `## <version>` changelog entry is missing or the build number didn't
increase — the full checklist is in [CLAUDE.md](../CLAUDE.md#auto-update-sparkle).
