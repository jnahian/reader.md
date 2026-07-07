# Reader.md (Swift / SwiftUI)

A native macOS rebuild of the markdown viewer using SwiftUI and AppKit. The whole shell — topbar, sidebar, file search, outline, folder management, file watching, and SF Symbol icons — is native SwiftUI. The markdown content pane is a `WKWebView` that renders through bundled JS engines, because Mermaid diagrams and LaTeX math have no native equivalent.

## Architecture

- **SwiftUI shell** — `ContentView` lays out a draggable topbar, a resizable/collapsible sidebar, the content pane, and a collapsible outline; overlays host the find bar and quick-open palette.
- **`AppState`** (`ObservableObject`, `@MainActor`) — roots, selection, theme, search, outline, typography, layout, history, and find/export triggers; persists to `UserDefaults`.
- **`FileScanner` / `RootFolder`** — recursive markdown-only tree scan, pruning `node_modules`, `.git`, etc.
- **`FolderWatcher`** — FSEvents subtree watcher with a debounced callback for live reload.
- **`MarkdownWebView`** — `NSViewRepresentable` around `WKWebView`. Swift ↔ JS bridge: Swift pushes markdown / theme / font settings via `evaluateJavaScript`; JS posts the outline, active heading, word count, scroll progress, and link clicks back through `WKScriptMessageHandler`. Native `WKWebView.find` powers in-page search; `createPDF` powers export.
- **`GlassPanel` / `VisualEffectView`** — chrome surfaces use Apple's **Liquid Glass** (`glassEffect`) on macOS 26 (Tahoe) and fall back to an `NSVisualEffectView` material on macOS 13–15. Glass is applied only to the navigation layer (topbar, sidebar, outline, find bar, quick-open), never behind scrolling content.
- **Bundled web assets** (`Resources/web`) — marked, highlight.js, KaTeX (+ fonts), Mermaid. No network access.

## Features

- **Open anything** — a single `.md` file (⌘O or double-click in Finder), whole folders, or a mix; set Reader.md as your default markdown handler
- **Multi-folder browser** — add any number of roots (multi-select, or drag folders onto the window); each is a collapsible section with a hover-to-reveal remove button, and roots reorder by drag
- **Drag-and-drop** — drop a markdown file onto the content pane to open it
- **Quick open** — ⌘P fuzzy file switcher across all roots, with keyboard navigation
- **History & recents** — back/forward (⌘[ / ⌘]) plus a managed recent-files list in the empty state
- **File filter** — ⌘F filters the tree live across all roots
- **In-page find** — ⇧⌘F native find bar with match highlighting (⌘G / ⇧⌘G for next/prev)
- **Outline** — collapsible right pane (⌘⇧O) with a sliding accent rail marker and scrollspy
- **Typography** — font size (⌘+ / ⌘− / ⌘0) and a wide/narrow reading-column toggle, both persisted
- **Finder-style chrome** — capsule search field, grouped rounded toolbar icon buttons, a "FOLDERS" section header with tinted icons and a full-width selection pill, and a bottom status bar (markdown file count, or word count / reading-time for the open file), mirroring the macOS 26 Finder
- **Reading feedback** — accent progress bar under the topbar; word count and reading time in the status bar
- **Code copy buttons**, **image click-to-zoom** lightbox, and hover **heading anchors**
- **Export to PDF** — ⌘E via the web view's native PDF renderer
- **Liquid Glass chrome** — on macOS 26 (Tahoe) the topbar, sidebar, outline, find bar, and quick-open palette use Apple's `glassEffect`; on macOS 13–15 they fall back to translucent `NSVisualEffectView` material. Collapsible + resizable sidebar (⌘\, width persisted); breadcrumb reveals the file in Finder
- **Syntax highlighting, Mermaid, LaTeX math** — via the bundled JS engines
- **YAML frontmatter** — rendered as a clean key/value table at the top of the document
- **Dark mode** — system / light / dark cycle, applied to both native chrome and web content
- **Live reload** — the open file re-renders (scroll preserved) and the tree refreshes on disk changes
- **Auto-update** — the packaged `.app` checks for and installs new releases via Sparkle
- **About panel** — version and credits from the standard macOS About window

## Keyboard shortcuts

| Shortcut | Action | Shortcut | Action |
|---|---|---|---|
| ⌘O | Add folder | ⌘P | Quick open |
| ⌘F | Filter files | ⇧⌘F | Find in page |
| ⌘G / ⇧⌘G | Find next / previous | ⌘[ / ⌘] | Back / forward |
| ⌘\ | Toggle sidebar | ⌘⇧O | Toggle outline |
| ⌘+ / ⌘− / ⌘0 | Text bigger / smaller / reset | ⌘E | Export PDF |

## Requirements

- **Runtime:** macOS 13+. Liquid Glass appears on macOS 26 (Tahoe); earlier versions get the `NSVisualEffectView` fallback automatically.
- **Build:** Xcode 26 (or a Swift 6.2+ toolchain with the macOS 26 SDK) is required to compile, because the `glassEffect` symbols only exist in that SDK. The deployment target stays at macOS 13, so the built app still runs on 13+.

## Run (quick, for development)

```bash
swift run
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
- The `WKWebView` is granted broad file read access so `file://` images referenced by your markdown resolve; all rendering assets are local — the only network access is Sparkle's auto-update check.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
conventions, and the PR flow. By participating you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) © Julkar Naen Nahian
