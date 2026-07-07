# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `swift run` — build and launch the app (unsandboxed executable; reads any folder you add).
- `swift build` / `swift build -c release` — compile only.
- `./make-app.sh` then `open "build/Reader.md.app"` — assemble a double-clickable `.app` (release binary + SwiftPM resource bundle + icns + Info.plist).
- `swift test` — runs the `ReaderMdTests` target (currently just `fuzzyScore`, the ⌘P ranker). Most of the app is UI/WKWebView/FSEvents; verify those by running the app.

**Build toolchain:** Requires Xcode 26 / Swift 6.2+ with the macOS 26 SDK, because the `glassEffect` (Liquid Glass) symbols only exist there. Deployment target stays macOS 13, so runtime code must guard 26-only APIs with availability checks and fall back to `NSVisualEffectView`.

## Architecture

Native macOS markdown viewer: SwiftUI/AppKit shell wrapping a single `WKWebView` that renders markdown. Everything except the content pane is native; the web view exists only because Mermaid and LaTeX have no native equivalent.

**Two-layer split:**
- **Native shell** — `ContentView` (layout: topbar, resizable/collapsible sidebar, content, collapsible outline; find bar + quick-open as overlays). `Sources/ReaderMd/Views/` holds the SwiftUI pieces.
- **Web content** — `MarkdownWebView` (`NSViewRepresentable` over `WKWebView`) loads bundled assets from `Sources/ReaderMd/Resources/web/` (marked, highlight.js, KaTeX + fonts, Mermaid, `bridge.js`). Loaded via `Bundle.resources` (a helper: `Bundle.main` in a packaged `.app`, falling back to `Bundle.module` under `swift run`). `make-app.sh` copies the resources into `Contents/Resources` and ad-hoc code-signs the bundle — the SwiftPM `.bundle` can't live at the `.app` root (where `Bundle.module` looks) because codesign rejects contents there.

**`AppState`** (`@MainActor ObservableObject`) is the single source of truth: roots, selection, theme, outline, typography, layout, history, find/export state. Persists to `UserDefaults`. Injected as `@EnvironmentObject`.

**Swift ↔ JS bridge** (`MarkdownWebView` ↔ `bridge.js`):
- Swift → JS: `evaluateJavaScript` calling `window.ReaderMd.*` (`setTheme`, `loadMarkdown`, `reloadMarkdown`, font/width setters).
- JS → Swift: `WKScriptMessageHandler` message names — `ready`, `toc`, `activeHeading`, `wordCount`, `progress`, `openExternal`, `openFile`. The handler updates `AppState`.
- Native `WKWebView.find` powers in-page search; `createPDF` powers ⌘E export.

**Token-bump pattern (important):** SwiftUI is declarative but some actions are imperative one-shots (force reload, find next/prev, export PDF, focus search). These are modeled as incrementing `Int` tokens on `AppState` (`reloadToken`, `findNextToken`, `findPrevToken`, `exportToken`) or `Bool` toggles (`focusSearch`). A view `.onChange` of the token fires the side effect. When adding a new imperative trigger, follow this pattern rather than calling into the web view directly.

**File tree:** `FileScanner` / `RootFolder` (`FileNode.swift`) do a recursive markdown-only scan, pruning `node_modules`, `.git`, etc. `FolderWatcher` (FSEvents) watches each root subtree with a debounced callback; on disk change it bumps `reloadToken` (re-render, scroll preserved) and refreshes the tree.

**Chrome / Liquid Glass:** `GlassPanel` applies `glassEffect` on macOS 26, falling back to `VisualEffectView` (an `NSVisualEffectView` wrapper) on 13–15. Glass is applied only to navigation layers (topbar, sidebar, outline, find bar, quick-open) — never behind scrolling content. Don't stack glass *surfaces*, but interactive glass *controls* may sit on a glass surface when grouped in a `GlassEffectContainer` — that's the sanctioned Tahoe pattern, used by the topbar buttons (`ToolbarIconButtonStyle` / `toolbarGlassCapsule`).

## Conventions

- The app is **not sandboxed** — folder access is direct paths, no security-scoped bookmarks. The `WKWebView` gets broad `file://` read access so markdown-referenced local images resolve. All rendering assets are bundled; the only network access is Sparkle's auto-update check (fetching the appcast + update DMG).
- Any macOS 26-only API needs an availability guard with a pre-26 fallback (deployment target is 13).

## Auto-update (Sparkle)

`SPUStandardUpdaterController` (`ReaderMdApp.swift`) drives auto-update; it only starts in the packaged `.app` (gated on `SUFeedURL` in Info.plist) so `swift run` doesn't error. `make-app.sh` bundles `Sparkle.framework` into `Contents/Frameworks`, adds the `@executable_path/../Frameworks` rpath, and injects `SUFeedURL`/`SUPublicEDKey`. The feed is `releases/latest/download/appcast.xml` on GitHub, so the newest release's appcast is always served. `release.sh` signs the DMG (EdDSA private key in the login keychain), runs `generate_appcast`, and uploads the DMG + appcast to a `v<version>` GitHub release. To cut a release: bump **both** `CFBundleShortVersionString` (display) and `CFBundleVersion` (the integer Sparkle actually compares — must increase every release) in `make-app.sh`, run `./make-app.sh`, then `./release.sh` (which refuses to publish if `CFBundleVersion` didn't increase past the published one). The binary is arm64-only, so updates are offered to Apple-silicon Macs only.
