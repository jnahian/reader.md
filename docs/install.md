# Install

## Requirements

- **Runtime:** macOS 13+. Liquid Glass appears on macOS 26 (Tahoe); earlier versions get the `NSVisualEffectView` fallback automatically.
- **Build:** Xcode 26 (or a Swift 6.2+ toolchain with the macOS 26 SDK) is required to compile, because the `glassEffect` symbols only exist in that SDK. The deployment target stays at macOS 13, so the built app still runs on 13+.

The binary is arm64-only, so Reader.md and its automatic updates are offered to
Apple-silicon Macs.

## Homebrew (recommended)

Reader.md ships a [Homebrew Cask](../Casks/reader-md.rb) in this repo. Because the
repo isn't named `homebrew-*`, tap it with its explicit URL once, trust the cask,
then install:

```bash
brew tap jnahian/reader.md https://github.com/jnahian/reader.md
brew trust --cask jnahian/reader.md/reader.md
brew install --cask reader-md
```

Upgrades come from the app's own Sparkle updater, so `brew upgrade` leaves the
installed build alone (`auto_updates true`). To uninstall — including preferences
and caches:

```bash
brew uninstall --cask reader-md      # remove the app
brew uninstall --zap --cask reader-md # also wipe ~/Library data
```

## Direct download

Grab `Reader.md.dmg` from the [latest release](https://github.com/jnahian/reader.md/releases/latest),
open it, and drag **Reader.md** to **Applications**. The app is ad-hoc signed but
not notarized, so the first launch needs one right-click → **Open** (see
[Clearing quarantine](#clearing-quarantine)).

## The `reader` command

Homebrew puts `reader` on your PATH automatically. If you installed from the DMG,
use **File → Install `reader` Command Line Tool…**, and launch the app once first
so macOS clears quarantine from the bundle. See [the CLI reference](cli.md).

## Clearing quarantine

The ad-hoc signature means a downloaded copy is **not** flagged as "damaged" — but because it isn't notarized with an Apple Developer ID, the first launch still shows *"Apple cannot check it for malicious software."* Clear it once, either way:

- **Right-click** the app → **Open** → **Open** in the dialog, or
- Terminal: `xattr -dr com.apple.quarantine "/path/to/Reader.md.app"`

For a launch with no prompt at all, sign with a Developer ID and notarize (Xcode's Archive flow).
