# Reader.md (Swift / SwiftUI)

**Website:** [reader-md.jnahian.me](https://reader-md.jnahian.me)

A native macOS rebuild of the markdown viewer using SwiftUI and AppKit. The whole shell — toolbar, sidebar, file search, outline, folder management, file watching, and SF Symbol icons — is native SwiftUI. The markdown content pane is a `WKWebView` that renders through bundled JS engines, because Mermaid diagrams and LaTeX math have no native equivalent.

## Architecture

- **SwiftUI shell** — the window's native toolbar (`Toolbar.swift`) over `ContentView`, which lays out a resizable/collapsible sidebar, the content pane, and a collapsible outline; overlays host the find bar and quick-open palette.
- **`AppState`** (`ObservableObject`, `@MainActor`) — roots, selection, theme, search, outline, typography, layout, history, and find/export triggers; persists to `UserDefaults`.
- **`FileScanner` / `RootFolder`** — recursive markdown-only tree scan, pruning `node_modules`, `.git`, etc.
- **`RemoteSpec` / `RemoteSync`** — a remote (SSH) folder is `rsync`'d read-only into a stable local cache dir, which registers as an ordinary root; `RemoteSync` builds the `rsync -e ssh` invocation (mirroring the scanner's include/ignore filters) and runs it via `Process`. Credentials come from the user's `~/.ssh` config/keys — none are stored in-app. The stable cache path keeps annotations intact across re-syncs.
- **`FolderWatcher`** — FSEvents subtree watcher with a debounced callback for live reload.
- **`MarkdownWebView`** — `NSViewRepresentable` around `WKWebView`. Swift ↔ JS bridge: Swift pushes markdown / theme / font settings via `evaluateJavaScript`; JS posts the outline, active heading, word count, scroll progress, and link clicks back through `WKScriptMessageHandler`. Native `WKWebView.find` powers in-page search; `createPDF` powers export.
- **`GlassPanel` / `VisualEffectView`** — chrome surfaces use Apple's **Liquid Glass** (`glassEffect`) on macOS 26 (Tahoe) and fall back to an `NSVisualEffectView` material on macOS 13–15. Glass is applied only to the navigation layer (sidebar, outline, find bar, quick-open), never behind scrolling content; the toolbar is native, so AppKit draws its glass.
- **Bundled web assets** (`Resources/web`) — marked, highlight.js, KaTeX (+ fonts), Mermaid. No network access.

## Features

- **Open anything** — a single `.md` file (⌘O or double-click in Finder), whole folders, or a mix; set Reader.md as your default markdown handler
- **Multi-folder browser** — add any number of roots (multi-select, or drag folders onto the window); each is a collapsible section with hover-to-reveal actions, and roots reorder by drag
- **Remote (SSH) folders** — add a folder from a VPS: Reader.md `rsync`s it read-only into a local cache and shows it like any root. Auto-syncs on launch (quietly), manual re-sync, edit-the-connection-in-place, and a cloud badge with sync/error state. Reuses your `~/.ssh` config and keys — no credentials stored. Add via the **Add Remote** button in the sidebar footer
- **Context menus** — right-click any file, folder, root, or recent for Open / Reveal in Finder / Copy Path / Remove (and Edit Connection · Re-sync on remote roots)
- **Drag-and-drop** — drop a markdown file onto the content pane to open it
- **Quick open** — ⌘P fuzzy file switcher across all roots, with keyboard navigation
- **History & recents** — back/forward (⌘[ / ⌘]) plus a managed recent-files list in the empty state
- **File filter** — ⌘F filters the tree live across all roots
- **In-page find** — ⇧⌘F native find bar with match highlighting (⌘G / ⇧⌘G for next/prev)
- **Outline** — collapsible right pane (⌘⇧O) with a sliding accent rail marker and scrollspy
- **Typography** — font size (⌘+ / ⌘− / ⌘0) and a narrow/wide/full-width reading column (⇧⌘\), both persisted
- **Finder-style chrome** — capsule search field; native toolbar controls grouped into capsules by function; a "FOLDERS" section header with tinted icons and a full-width selection pill; and a bottom status bar (markdown file count, or word count / reading-time for the open file), mirroring the macOS 26 Finder
- **Reading feedback** — accent progress bar under the toolbar; word count and reading time in the status bar
- **Code copy buttons**, **image click-to-zoom** lightbox, and hover **heading anchors**
- **Export to PDF** (⌘E) and **manual reload** (⌘R) — toolbar buttons on the right, plus the web view's native PDF renderer
- **Liquid Glass chrome** — on macOS 26 (Tahoe) the native toolbar, sidebar, outline, find bar, and quick-open palette all read as Liquid Glass; on macOS 13–15 they fall back to translucent `NSVisualEffectView` material. Collapsible + resizable sidebar (⌘B, width persisted); the title's proxy icon reveals the file in Finder
- **Syntax highlighting, Mermaid, LaTeX math** — via the bundled JS engines
- **YAML frontmatter** — rendered as a clean key/value table at the top of the document
- **Dark mode** — system / light / dark cycle, applied to both native chrome and web content
- **Live reload** — the open file re-renders (scroll preserved) and the tree refreshes on disk changes
- **Auto-update** — the packaged `.app` checks for and installs new releases via Sparkle
- **About panel** — version and credits from the standard macOS About window

## Keyboard shortcuts

| Shortcut | Action | Shortcut | Action |
|---|---|---|---|
| ⌘O | Open file | ⌘P | Quick open |
| ⇧⌘A | Add folder | ⌥⌘A | Add remote folder |
| ⌘F | Filter files | ⇧⌘F | Find in page |
| ⌘G / ⇧⌘G | Find next / previous | ⌘[ / ⌘] | Back / forward |
| ⌘B | Toggle sidebar | ⇧⌘B | Toggle outline |
| ⌘+ / ⌘− / ⌘0 | Text bigger / smaller / reset | ⌘E | Export PDF |
| ⌘R | Reload | | |

## Command line

```
reader <file.md>                   open a markdown file
reader <folder>                    add a folder to the sidebar
reader .                           add the current directory
reader remote me@vps:/srv/docs     add a remote (SSH) folder — opens a confirmation sheet
reader ls                          list configured folders
reader rm <name|path>              remove a folder
git diff | reader -                open piped markdown
```

Homebrew puts `reader` on your PATH automatically. If you installed from the DMG, use
**File → Install `reader` Command Line Tool…**, and launch the app once first so macOS clears
quarantine from the bundle.

`reader` drives the app rather than replacing it: each command hands a `readermd://` URL to
Reader.md, which does the work. `reader ls` reads the app's saved folders directly, so a folder
added a moment ago may take a beat to appear.

It behaves in scripts: a bad path, an unknown option, or a malformed command exits **1** with the
reason on stderr, so `reader remote "$HOST:$DIR" || handle_error` sees the failure. `reader` with
no arguments (or `--help`) prints usage to stdout and exits 0.

## Requirements

- **Runtime:** macOS 13+. Liquid Glass appears on macOS 26 (Tahoe); earlier versions get the `NSVisualEffectView` fallback automatically.
- **Build:** Xcode 26 (or a Swift 6.2+ toolchain with the macOS 26 SDK) is required to compile, because the `glassEffect` symbols only exist in that SDK. The deployment target stays at macOS 13, so the built app still runs on 13+.

## Install

### Homebrew (recommended)

Reader.md ships a [Homebrew Cask](Casks/reader-md.rb) in this repo. Because the
repo isn't named `homebrew-*`, tap it with its explicit URL once, then install:

```bash
brew tap jnahian/reader.md https://github.com/jnahian/reader.md
brew install --cask reader-md
```

Upgrades come from the app's own Sparkle updater, so `brew upgrade` leaves the
installed build alone (`auto_updates true`). To uninstall — including preferences
and caches:

```bash
brew uninstall --cask reader-md      # remove the app
brew uninstall --zap --cask reader-md # also wipe ~/Library data
```

### Direct download

Grab `Reader.md.dmg` from the [latest release](https://github.com/jnahian/reader.md/releases/latest),
open it, and drag **Reader.md** to **Applications**. The app is ad-hoc signed but
not notarized, so the first launch needs one right-click → **Open** (see
[Sharing with teammates](#sharing-with-teammates)).

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

### Sharing with teammates

The ad-hoc signature means a downloaded copy is **not** flagged as "damaged" — but because it isn't notarized with an Apple Developer ID, the first launch still shows *"Apple cannot check it for malicious software."* Teammates clear it once, either way:

- **Right-click** the app → **Open** → **Open** in the dialog, or
- Terminal: `xattr -dr com.apple.quarantine "/path/to/Reader.md.app"`

For a launch with no prompt at all, sign with a Developer ID and notarize (Xcode's Archive flow).

## Open in Xcode

`File → Open…` this project folder (SwiftPM package). Select the `ReaderMd` scheme and Run. Use Xcode's Archive flow for a signed, distributable build.

## Notes

- The app is **not** sandboxed, so it reads user-selected folders directly (no security-scoped bookmarks). For Mac App Store distribution you'd enable the sandbox and wrap folder access in bookmarks.
- The `WKWebView` is granted broad file read access so `file://` images referenced by your markdown resolve; all rendering assets are local — the only network access is Sparkle's auto-update check and, for remote folders, `rsync`/`ssh` to the hosts you add.
- **Remote folders** require `rsync` and `ssh` on your Mac (both ship with macOS) and rely on your `~/.ssh` config for reaching the host. Sync is read-only and pull-based (on launch + manual re-sync); Reader.md never writes back to the remote.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
conventions, and the PR flow. By participating you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) © Julkar Naen Nahian
