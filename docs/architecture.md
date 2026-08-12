---
title: Architecture
category: Internals
order: 30
summary: How the native shell and the WKWebView content pane fit together.
---

# Architecture

A native macOS markdown viewer: the whole shell — toolbar, sidebar, file search,
outline, folder management, file watching, and SF Symbol icons — is native
SwiftUI. The markdown content pane is a `WKWebView` that renders through bundled
JS engines, because Mermaid diagrams and LaTeX math have no native equivalent.

- **SwiftUI shell** — the window's native toolbar (`Toolbar.swift`) over `ContentView`, which lays out a resizable/collapsible sidebar, the content pane, and a collapsible outline; overlays host the find bar and quick-open palette.
- **`AppState`** (`ObservableObject`, `@MainActor`) — roots, selection, theme, search, outline, typography, layout, history, and find/export triggers; persists to `UserDefaults`.
- **`FileScanner` / `RootFolder`** — recursive markdown-only tree scan, pruning `node_modules`, `.git`, etc. In a repo it also prunes what `git ls-files --ignored` reports. Git is run *in the scanned folder*, not the repo root: that limits the walk to the subtree actually on screen (a root inside a monorepo, or under a `$HOME` that is itself a repo, would otherwise re-enumerate the whole thing on every rescan) and makes git's output already relative to that folder, so no path from the two sides ever has to be compared — git answers in fully resolved paths while `FileManager` and the sidebar don't. The same call doubles as the is-a-repo test.
- **`RemoteSpec` / `RemoteSync`** — a remote folder is synced read-only into a stable local cache dir, which registers as an ordinary root: `rsync -e ssh` for an SSH destination, `git clone` / `git pull --ff-only` when the spec carries a `gitURL` (the field's presence is what makes it a repo, and it's optional so specs saved before repos existed still decode). SSH credentials come from the user's `~/.ssh` config/keys and git's from its own configuration — none are stored in-app, and git runs with `GIT_TERMINAL_PROMPT=0` so it can never block the sync on a prompt. The stable cache path keeps annotations intact across re-syncs.
- **`GitDiff`** — every git invocation in the app, from one `Process` runner: sidebar status badges, the split diff a `DiffScope` selects (`unstaged` / `staged` / `all` / `ref(branch)`), the branch list that scope menu offers, and the ignore set the scanner prunes with.
- **`FolderWatcher`** — FSEvents subtree watcher with a debounced callback for live reload.
- **`MarkdownWebView`** — `NSViewRepresentable` around `WKWebView`. Swift ↔ JS bridge: Swift pushes markdown / theme / font settings via `evaluateJavaScript`; JS posts the outline, active heading, word count, scroll progress, and link clicks back through `WKScriptMessageHandler`. Native `WKWebView.find` powers in-page search. ⌘E export has two layouts: Continuous renders one long page via `createPDF`, while the default Page by Page runs `printOperation(with:)` headlessly and then repaints the finished PDF with the theme background (the print engine leaves paper margins unpainted), carrying the link annotations across the rewrite.
- **`GlassPanel` / `VisualEffectView`** — chrome surfaces use Apple's **Liquid Glass** (`glassEffect`) on macOS 26 (Tahoe) and fall back to an `NSVisualEffectView` material on macOS 13–15. Glass is applied only to the navigation layer (sidebar, outline, find bar, quick-open), never behind scrolling content; the toolbar is native, so AppKit draws its glass.
- **Bundled web assets** (`Resources/web`) — marked, highlight.js, KaTeX (+ fonts), Mermaid. No network access.

## Notes

- The app is **not** sandboxed, so it reads user-selected folders directly (no security-scoped bookmarks). For Mac App Store distribution you'd enable the sandbox and wrap folder access in bookmarks.
- The `WKWebView` is granted broad file read access so `file://` images referenced by your markdown resolve; all rendering assets are local — the only network access is Sparkle's auto-update check and, for remote folders, `rsync`/`ssh` or `git` to the hosts you add.
- **Remote folders** require `rsync` and `ssh` on your Mac (both ship with macOS) and rely on your `~/.ssh` config for reaching the host; cloned repositories require `git`. Sync is read-only and pull-based (on launch + manual re-sync); Reader.md never writes back to the remote, and a clone is only ever fast-forwarded.

`CLAUDE.md` in the repo root goes deeper — the token-bump pattern for imperative
actions, the `reader` CLI's URL-dispatch design, and how Sparkle releases are cut.
[`markup-model.md`](markup-model.md) is the design sketch for the anchored
highlight / annotation / comment model.
