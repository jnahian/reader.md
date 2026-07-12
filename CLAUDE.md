# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `swift run ReaderMd` — build and launch the app (unsandboxed executable; reads any folder you add).
- `swift build` / `swift build -c release` — compile only.
- `./make-app.sh` then `open "build/Reader.md.app"` — assemble a double-clickable `.app` (release binary + SwiftPM resource bundle + icns + Info.plist).
- `swift test` — runs the `ReaderMdTests` target (currently just `fuzzyScore`, the ⌘P ranker). Most of the app is UI/WKWebView/FSEvents; verify those by running the app.

**Build toolchain:** Requires Xcode 26 / Swift 6.2+ with the macOS 26 SDK, because the `glassEffect` (Liquid Glass) symbols only exist there. Deployment target stays macOS 13, so runtime code must guard 26-only APIs with availability checks and fall back to `NSVisualEffectView`.

## Architecture

Native macOS markdown viewer: SwiftUI/AppKit shell wrapping a single `WKWebView` that renders markdown. Everything except the content pane is native; the web view exists only because Mermaid and LaTeX have no native equivalent.

**Two-layer split:**
- **Native shell** — `ContentView` (layout: resizable/collapsible sidebar, content, collapsible outline; find bar + quick-open as overlays) under the window's native toolbar (`Toolbar.swift`, applied as `.readerToolbar()`). `Sources/ReaderMd/Views/` holds the SwiftUI pieces.
- **Web content** — `MarkdownWebView` (`NSViewRepresentable` over `WKWebView`) loads bundled assets from `Sources/ReaderMd/Resources/web/` (marked, highlight.js, KaTeX + fonts, Mermaid, `bridge.js`). Loaded via `Bundle.resources` (a helper: `Bundle.main` in a packaged `.app`, falling back to `Bundle.module` under `swift run`). `make-app.sh` copies the resources into `Contents/Resources` and ad-hoc code-signs the bundle — the SwiftPM `.bundle` can't live at the `.app` root (where `Bundle.module` looks) because codesign rejects contents there.

**`AppState`** (`@MainActor ObservableObject`) is the single source of truth: roots, selection, theme, outline, typography, layout, history, find/export state. Persists to `UserDefaults`. Injected as `@EnvironmentObject`.

**Swift ↔ JS bridge** (`MarkdownWebView` ↔ `bridge.js`):
- Swift → JS: `evaluateJavaScript` calling `window.ReaderMd.*` (`setTheme`, `loadMarkdown`, `reloadMarkdown`, font/width setters).
- JS → Swift: `WKScriptMessageHandler` message names — `ready`, `toc`, `activeHeading`, `wordCount`, `progress`, `openExternal`, `openFile`. The handler updates `AppState`.
- Native `WKWebView.find` powers in-page search; `createPDF` powers ⌘E export.

**Token-bump pattern (important):** SwiftUI is declarative but some actions are imperative one-shots (force reload, find next/prev, export PDF, focus search). These are modeled as incrementing `Int` tokens on `AppState` (`reloadToken`, `findNextToken`, `findPrevToken`, `exportToken`) or `Bool` toggles (`focusSearch`). A view `.onChange` of the token fires the side effect. When adding a new imperative trigger, follow this pattern rather than calling into the web view directly.

**File tree:** `FileScanner` / `RootFolder` (`FileNode.swift`) do a recursive markdown-only scan, pruning `node_modules`, `.git`, etc. `FolderWatcher` (FSEvents) watches each root subtree with a debounced callback; on disk change it bumps `reloadToken` (re-render, scroll preserved) and refreshes the tree.

**Chrome / Liquid Glass:** `GlassPanel` applies `glassEffect` on macOS 26, falling back to `VisualEffectView` (an `NSVisualEffectView` wrapper) on 13–15. Glass is applied only to navigation layers (sidebar, outline, find bar, quick-open) — never behind scrolling content. The window chrome is the **native toolbar** (`.toolbar` in `Toolbar.swift`), so AppKit draws its glass and groups items into capsules: use `ToolbarItemGroup` for a cluster rather than styling one yourself.

**`reader` CLI** (`Sources/ReaderCLI/`, a second executable target, ships at `Reader.md.app/Contents/MacOS/reader`) — never touches `UserDefaults` directly. `reader ls` reads the app's saved folders directly (`Prefs.swift`, read-only); every other verb (`open`, `remote`, `rm`, `-` for piped stdin) turns argv into a `readermd://` URL (`Route.swift`) and hands it to the running/launched app via `NSWorkspace` (`Dispatch.swift`), which does the actual work, including any preference writes. The app is the single writer of its own preferences — the CLI never writes them, to avoid racing `AppState`'s in-memory `roots` re-persisting over a CLI write.

## Conventions

- The app is **not sandboxed** — folder access is direct paths, no security-scoped bookmarks. The `WKWebView` gets broad `file://` read access so markdown-referenced local images resolve. All rendering assets are bundled; the only network access is Sparkle's auto-update check (fetching the appcast + update DMG).
- Any macOS 26-only API needs an availability guard with a pre-26 fallback (deployment target is 13).

## Auto-update (Sparkle)

`SPUStandardUpdaterController` (`ReaderMdApp.swift`) drives auto-update; it only starts in the packaged `.app` (gated on `SUFeedURL` in Info.plist) so `swift run` doesn't error. `make-app.sh` bundles `Sparkle.framework` into `Contents/Frameworks`, adds the `@executable_path/../Frameworks` rpath, and injects `SUFeedURL`/`SUPublicEDKey`. The feed is `releases/latest/download/appcast.xml` on GitHub, so the newest release's appcast is always served. `release.sh` signs the DMG (EdDSA private key in the login keychain), runs `generate_appcast`, and uploads the DMG + appcast to a `v<version>` GitHub release. **Release notes** come from the changelog, in two places: `release.sh` extracts the `## <version>` section of `Sources/ReaderMd/Resources/docs/CHANGELOG.md`, stages it beside the DMG as `Reader.md.md` (`generate_appcast` pairs release notes to an archive by basename), and passes `--embed-release-notes` so they land in the appcast as `<description sparkle:format="markdown">` — that's what Sparkle's update prompt shows. The same bundled file is what `AppState.checkWhatsNew()` opens on the first launch after an update. So the changelog entry must exist *before* the release: `release.sh` refuses to publish a version with no section, because both screens would otherwise show the previous version's notes.

To cut a release: add the `## <version>` changelog entry, bump `CFBundleShortVersionString` (display) in `make-app.sh`, run `./make-app.sh`, then `./release.sh` (which refuses to publish if `CFBundleVersion` didn't increase past the published one, or if the changelog entry is missing). `CFBundleVersion` — the integer Sparkle actually compares — is derived from the build time (`date +%Y%m%d%H%M`) so it's always monotonic; no manual bump. Follow the `release` skill for the full checklist (changelog, About fallback, commit-before-tag). The binary is arm64-only, so updates are offered to Apple-silicon Macs only.
