# Architecture

A native macOS markdown viewer: the whole shell — toolbar, sidebar, file search,
outline, folder management, file watching, and SF Symbol icons — is native
SwiftUI. The markdown content pane is a `WKWebView` that renders through bundled
JS engines, because Mermaid diagrams and LaTeX math have no native equivalent.

- **SwiftUI shell** — the window's native toolbar (`Toolbar.swift`) over `ContentView`, which lays out a resizable/collapsible sidebar, the content pane, and a collapsible outline; overlays host the find bar and quick-open palette.
- **`AppState`** (`ObservableObject`, `@MainActor`) — roots, selection, theme, search, outline, typography, layout, history, and find/export triggers; persists to `UserDefaults`.
- **`FileScanner` / `RootFolder`** — recursive markdown-only tree scan, pruning `node_modules`, `.git`, etc.
- **`RemoteSpec` / `RemoteSync`** — a remote (SSH) folder is `rsync`'d read-only into a stable local cache dir, which registers as an ordinary root; `RemoteSync` builds the `rsync -e ssh` invocation (mirroring the scanner's include/ignore filters) and runs it via `Process`. Credentials come from the user's `~/.ssh` config/keys — none are stored in-app. The stable cache path keeps annotations intact across re-syncs.
- **`FolderWatcher`** — FSEvents subtree watcher with a debounced callback for live reload.
- **`MarkdownWebView`** — `NSViewRepresentable` around `WKWebView`. Swift ↔ JS bridge: Swift pushes markdown / theme / font settings via `evaluateJavaScript`; JS posts the outline, active heading, word count, scroll progress, and link clicks back through `WKScriptMessageHandler`. Native `WKWebView.find` powers in-page search; `createPDF` powers export.
- **`GlassPanel` / `VisualEffectView`** — chrome surfaces use Apple's **Liquid Glass** (`glassEffect`) on macOS 26 (Tahoe) and fall back to an `NSVisualEffectView` material on macOS 13–15. Glass is applied only to the navigation layer (sidebar, outline, find bar, quick-open), never behind scrolling content; the toolbar is native, so AppKit draws its glass.
- **Bundled web assets** (`Resources/web`) — marked, highlight.js, KaTeX (+ fonts), Mermaid. No network access.

## Notes

- The app is **not** sandboxed, so it reads user-selected folders directly (no security-scoped bookmarks). For Mac App Store distribution you'd enable the sandbox and wrap folder access in bookmarks.
- The `WKWebView` is granted broad file read access so `file://` images referenced by your markdown resolve; all rendering assets are local — the only network access is Sparkle's auto-update check and, for remote folders, `rsync`/`ssh` to the hosts you add.
- **Remote folders** require `rsync` and `ssh` on your Mac (both ship with macOS) and rely on your `~/.ssh` config for reaching the host. Sync is read-only and pull-based (on launch + manual re-sync); Reader.md never writes back to the remote.

`CLAUDE.md` in the repo root goes deeper — the token-bump pattern for imperative
actions, the `reader` CLI's URL-dispatch design, and how Sparkle releases are cut.
[`markup-model.md`](markup-model.md) is the design sketch for the anchored
highlight / annotation / comment model.
