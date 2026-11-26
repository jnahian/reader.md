---
title: Install
category: Getting started
order: 1
summary: Homebrew or the DMG, what it needs, how updates arrive, and clearing the first-launch warning.
related: [faq, features, cli, building]
---

# Install

## Requirements

macOS 13 or later, on an Apple-silicon Mac. The binary is arm64-only, so the
app runs on Apple silicon only. If you are
not sure which you have,  → **About This Mac** says so on the first line.

Liquid Glass appears on macOS 26 (Tahoe); 13 through 15 get the
`NSVisualEffectView` fallback automatically, with no setting to choose between
them.

Building from source needs more than running it does — see
[Building](building.md).

## Homebrew

Reader.md ships a [Homebrew Cask](../Casks/reader-md.rb) in this repo. Because
the repo isn't named `homebrew-*`, tap it with its explicit URL once. Homebrew
won't load a cask from a tap outside its own until you trust it, so trust the
cask, then install:

```bash
brew tap jnahian/reader.md https://github.com/jnahian/reader.md
brew trust --cask jnahian/reader.md/reader-md
brew install --cask reader-md
```

This also puts `reader` on your PATH.

## Direct download

Grab `Reader.md.dmg` from the
[latest release](https://github.com/jnahian/reader.md/releases/latest), open it,
and drag **Reader.md** to **Applications**. The app is ad-hoc signed but not
notarized, so macOS asks you to approve its first launch — see
[Clearing quarantine](#clearing-quarantine).

For the `reader` command, use **File → Install `reader` Command Line Tool…**
once the app is running. See [the CLI reference](cli.md). With `reader`
installed, an [agent skill](agent-skill.md) lets your coding agent open what it
writes.

## Updates

Once a day, the packaged app asks GitHub whether there's a newer release. When
there is, it tells you, and **Download…** opens the release page: download the
DMG and replace the app in Applications, as you did to install it. macOS asks
you to approve the new version's first launch, the same way — see
[Clearing quarantine](#clearing-quarantine). Reader.md never downloads or
installs anything itself. **Later** dismisses the notice
until the next day's check. **Reader.md → Check for Updates…** asks straight
away, and also tells you when you're up to date.

The first launch after an update opens the changelog, so you can see what
changed without going looking for it.

With Homebrew, `brew upgrade` installs the new version, which needs that same
approval.

### Updating from 1.23.0 or earlier

Up to 1.23.0, Reader.md installed its own updates through Sparkle. It stopped
in 1.24.0, because the key that signed those updates was lost. An older version
still checks, but when it finds 1.24.0 or later it offers **Learn More…**
instead of installing: download that version once by hand, and from then on the
app tells you about new versions itself.

## Uninstalling

```bash
brew uninstall --cask reader-md         # remove the app
brew uninstall --zap --cask reader-md   # and everything it stored
```

`--zap` is the one that removes your data: preferences, caches, and
`~/Library/Application Support/Reader.md`, which is where highlights, notes, and
the cached copies of remote folders live. Without it those survive an uninstall
— which is what you want if you are reinstalling, and not if you are done.

Nothing is stored inside your markdown, so no folder you added is touched either
way.

## Clearing quarantine

The ad-hoc signature means a downloaded copy is **not** flagged as "damaged" —
but because it isn't notarized with an Apple Developer ID, macOS blocks the
first launch with a warning that it can't check the app for malware. Approve it
one of these ways:

- **macOS 15 or later:** open the app and close the warning, then go to
  **System Settings → Privacy & Security**, click **Open Anyway** beside
  Reader.md, and confirm. Right-clicking → **Open** no longer gets past the
  warning on these versions.
- **macOS 13 or 14:** right-click the app → **Open** → **Open** in the dialog.
- **Any version**, in Terminal:
  `xattr -dr com.apple.quarantine "/Applications/Reader.md.app"`

**Each update needs this again**, whether it came from the DMG or from
`brew upgrade`. An ad-hoc signature identifies only that exact build, so neither
macOS nor Homebrew (which otherwise carries your approval over to an upgrade)
can tell a new version from a different app. The `xattr` line is the quickest
way through.

For a launch with no prompt at all, sign with a Developer ID and notarize
(Xcode's Archive flow).
