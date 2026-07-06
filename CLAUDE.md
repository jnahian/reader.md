# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `swift run` — build and launch the app (unsandboxed executable; reads any folder you add).
- `swift build` / `swift build -c release` — compile only.
- `./make-app.sh` then `open "build/Reader.md.app"` — assemble a double-clickable `.app` (release binary + SwiftPM resource bundle + icns + Info.plist).
- No test target exists. Verify changes by running the app.

**Build toolchain:** Requires Xcode 26 / Swift 6.2+ with the macOS 26 SDK, because the `glassEffect` (Liquid Glass) symbols only exist there. Deployment target stays macOS 13, so runtime code must guard 26-only APIs with availability checks and fall back to `NSVisualEffectView`.

## Architecture

Native macOS markdown viewer: SwiftUI/AppKit shell wrapping a single `WKWebView` that renders markdown. Everything except the content pane is native; the web view exists only because Mermaid and LaTeX have no native equivalent.

**Two-layer split:**
- **Native shell** — `ContentView` (layout: topbar, resizable/collapsible sidebar, content, collapsible outline; find bar + quick-open as overlays). `Sources/ReaderMd/Views/` holds the SwiftUI pieces.
- **Web content** — `MarkdownWebView` (`NSViewRepresentable` over `WKWebView`) loads bundled assets from `Sources/ReaderMd/Resources/web/` (marked, highlight.js, KaTeX + fonts, Mermaid, `bridge.js`). Loaded via `Bundle.module` — assets are copied resources, so `make-app.sh` places the `.bundle` next to the executable.

**`AppState`** (`@MainActor ObservableObject`) is the single source of truth: roots, selection, theme, outline, typography, layout, history, find/export state. Persists to `UserDefaults`. Injected as `@EnvironmentObject`.

**Swift ↔ JS bridge** (`MarkdownWebView` ↔ `bridge.js`):
- Swift → JS: `evaluateJavaScript` calling `window.ReaderMd.*` (`setTheme`, `loadMarkdown`, `reloadMarkdown`, font/width setters).
- JS → Swift: `WKScriptMessageHandler` message names — `ready`, `toc`, `activeHeading`, `wordCount`, `progress`, `openExternal`, `openFile`. The handler updates `AppState`.
- Native `WKWebView.find` powers in-page search; `createPDF` powers ⌘E export.

**Token-bump pattern (important):** SwiftUI is declarative but some actions are imperative one-shots (force reload, find next/prev, export PDF, focus search). These are modeled as incrementing `Int` tokens on `AppState` (`reloadToken`, `findNextToken`, `findPrevToken`, `exportToken`) or `Bool` toggles (`focusSearch`). A view `.onChange` of the token fires the side effect. When adding a new imperative trigger, follow this pattern rather than calling into the web view directly.

**File tree:** `FileScanner` / `RootFolder` (`FileNode.swift`) do a recursive markdown-only scan, pruning `node_modules`, `.git`, etc. `FolderWatcher` (FSEvents) watches each root subtree with a debounced callback; on disk change it bumps `reloadToken` (re-render, scroll preserved) and refreshes the tree.

**Chrome / Liquid Glass:** `GlassPanel` applies `glassEffect` on macOS 26, falling back to `VisualEffectView` (an `NSVisualEffectView` wrapper) on 13–15. Glass is applied only to navigation layers (topbar, sidebar, outline, find bar, quick-open) — never behind scrolling content.

## Conventions

- The app is **not sandboxed** — folder access is direct paths, no security-scoped bookmarks. The `WKWebView` gets broad `file://` read access so markdown-referenced local images resolve. Nothing is fetched from the network; all rendering assets are bundled.
- Any macOS 26-only API needs an availability guard with a pre-26 fallback (deployment target is 13).
