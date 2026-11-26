---
title: Install
category: Getting started
order: 1
summary: Homebrew or the DMG, what it needs, how updates arrive, and clearing the first-launch warning.
related: [faq, features, cli, building]
---

# Install

## Requirements

macOS 13 or later, on an Apple-silicon Mac. The binary is arm64-only, so both
the app and its automatic updates are offered to Apple silicon only. If you are
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

The packaged app checks for updates through Sparkle on launch and offers what
it finds; accepting installs it in place. **Reader.md → Check for Updates…**
asks straight away.

**Remind Later** dismisses an offer without taking it; the next check offers it
again. **Skip This Version** passes on that release for good.

The first launch after an update opens the changelog, so you can see what
changed without going looking for it.

Homebrew defers to that (`auto_updates true`), so `brew upgrade` leaves an
already-updated build alone rather than replacing it with the cask's version.

Updates are offered to Apple-silicon Macs only, for the same reason the install
is.

### Updating from 1.23.0 or earlier

From 1.24.0, updates are signed with a new key, because the one that 1.23.0 and
earlier trust was lost. Those versions can't verify the new signature, so
instead of installing the update they offer **Learn More…**, which opens the
release page. Download the DMG there and replace the app in Applications, once:
macOS asks you to approve its first launch, as it did when you installed it.
With Homebrew, `brew upgrade` installs it instead. From then on, updates install
themselves again.

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

Updates installed through **Check for Updates…** don't need this again. A copy
you download yourself does, and so does one that `brew upgrade` installs.

For a launch with no prompt at all, sign with a Developer ID and notarize
(Xcode's Archive flow).
