# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `swift run ReaderMd` — build and launch the app (unsandboxed executable; reads any folder you add).
- `swift build` / `swift build -c release` — compile only.
- `./make-app.sh` then `open "build/Reader.md.app"` — assemble a double-clickable `.app` (release binary + SwiftPM resource bundle + icns + Info.plist).
- `swift test` — runs the `ReaderMdTests` target (pure logic only: ⌘P matching/recents, CLI routing, marks, favorites, git diff/ignore, remote specs, export layout, reading position/theme, stdin docs, editor gates). Most of the app is UI/WKWebView/FSEvents; verify those by running the app. `ShortcutDocTests` is the one that guards documentation: every shortcut in the bundled `SHORTCUTS.md` has to appear in `docs/features.md`, so a shortcut change that skips the docs fails the suite.
- `cd web && npm run build` — build the marketing site. See `web/CLAUDE.md`.

**Build toolchain:** Requires Xcode 26 / Swift 6.2+ with the macOS 26 SDK, because the `glassEffect` (Liquid Glass) symbols only exist there. Deployment target stays macOS 13, so runtime code must guard 26-only APIs with availability checks and fall back to `NSVisualEffectView`.

## Architecture

Native macOS markdown viewer: SwiftUI/AppKit shell wrapping a single `WKWebView` that renders markdown. Everything except the content pane is native; the web view exists only because Mermaid and LaTeX have no native equivalent.

**Two-layer split:**
- **Native shell** — `ContentView` (layout: resizable/collapsible sidebar, content, collapsible outline; find bar + quick-open as overlays) under the window's native toolbar (`Toolbar.swift`, applied as `.readerToolbar()`). `Sources/ReaderMd/Views/` holds the SwiftUI pieces.
  - There is a **second window**: the `SwiftUI.Settings` scene (⌘,, `SettingsView`). It must be written fully qualified — `Models/Settings.swift` declares a module-scope `enum Settings` that shadows the scene — and it's a sibling of `ContentView`, not a child, so the environment object and colour scheme are passed in again. Its existence is also why ⌘W is fiddly: `AppDelegate` intercepts ⌘W to close the *document* rather than the window, and has to hand it back whenever Settings is the key window.
- **Web content** — `MarkdownWebView` (`NSViewRepresentable` over `WKWebView`) loads bundled assets from `Sources/ReaderMd/Resources/web/` (marked, highlight.js, KaTeX + fonts, Mermaid, `bridge.js`). Loaded via `Bundle.resources` (a helper: `Bundle.main` in a packaged `.app`, falling back to `Bundle.module` under `swift run`). `make-app.sh` copies the resources into `Contents/Resources` and ad-hoc code-signs the bundle — the SwiftPM `.bundle` can't live at the `.app` root (where `Bundle.module` looks) because codesign rejects contents there.

**`AppState`** (`@MainActor ObservableObject`) is the single source of truth: roots, selection, theme, outline, typography, layout, history, find/export state, external-editor preference. Persists to `UserDefaults` (`Models/Settings.swift` owns the keys and the load/save calls). Injected as `@EnvironmentObject`.

The one deliberate exception is **`ReadingState`** (`Models/ReadingState.swift`) — scroll progress and the active heading, published at scroll rate (~60–120/s). It's a second `ObservableObject`, injected alongside `AppState`, because while those two values lived on `AppState` every scroll event invalidated all ~3k sidebar rows. Anything published at scroll or keystroke rate belongs there, not on `AppState`.

**Marks (highlights, notes, comment threads)** — one anchored entity, not three types: a `Mark` (`Models/Mark.swift`) has a colour, a `TextAnchor`, and `comments` — empty is a highlight, one is a note, more is a thread — plus `resolved`. `MarkStore` persists them to `~/Library/Application Support/Reader.md/marks/<sha256(path)>.json` — keyed by path, so the markdown itself is never written to, and a rename loses the marks; a mark whose anchor text is gone is flagged orphaned rather than dropped (`OrphanedMarksBadge`). `MarkPopoverView` is the editor, `ResolvedThreadsToggle` the toolbar's show/hide. `docs/markup-model.md` is the design sketch behind the model.

**Git** — `Models/GitDiff.swift` shells out to `git` for status badges, the side-by-side diff, and the scope (unstaged / staged / all / a branch, picked in `DiffScopePicker`). Diff mode swaps the outline's contents from headings to hunks.

**Remote roots** — `RemoteSpec` describes an SSH or clone source; `RemoteSync` `rsync`s or `git clone`/`pull --ff-only`s it read-only into a local cache, using the user's own `~/.ssh` and git credentials and storing none. `AddRemoteView` is the sheet.

**Swift ↔ JS bridge** (`MarkdownWebView` ↔ `bridge.js`):
- Swift → JS: `evaluateJavaScript` calling `window.ReaderMd.*` (`setTheme`, `loadMarkdown`, `reloadMarkdown`, font/width setters).
- JS → Swift: `WKScriptMessageHandler` message names — `ready`, `toc`, `activeHeading`, `wordCount`, `progress`, `openExternal`, `openFile`. The handler updates `AppState`.
- Native `WKWebView.find` powers in-page search; `createPDF` powers ⌘E export.

**Token-bump pattern (important):** SwiftUI is declarative but some actions are imperative one-shots (force reload, find next/prev, export PDF, focus search). These are modeled as incrementing `Int` tokens on `AppState` (`reloadToken`, `findNextToken`, `findPrevToken`, `exportToken`) or `Bool` toggles (`focusSearch`). A view `.onChange` of the token fires the side effect. When adding a new imperative trigger, follow this pattern rather than calling into the web view directly.

**File tree:** `FileScanner` / `RootFolder` (`FileNode.swift`) do a recursive markdown-only scan, pruning `node_modules`, `.git`, etc. `FolderWatcher` (FSEvents) watches each root subtree with a debounced callback; on disk change it bumps `reloadToken` (re-render, scroll preserved) and refreshes the tree.

**Chrome / Liquid Glass:** `GlassPanel` applies `glassEffect` on macOS 26, falling back to `VisualEffectView` (an `NSVisualEffectView` wrapper) on 13–15. Glass is applied only to navigation layers (sidebar, outline, find bar, quick-open) — never behind scrolling content. The window chrome is the **native toolbar** (`.toolbar` in `Toolbar.swift`), so AppKit draws its glass and groups items into capsules: use `ToolbarItemGroup` for a cluster rather than styling one yourself.

**`reader` CLI** (`Sources/ReaderCLI/`, a second executable target, ships at `Reader.md.app/Contents/MacOS/reader`) — never touches `UserDefaults` directly. `reader ls` reads the app's saved folders directly (`Prefs.swift`, read-only); every other verb (`open`, `remote`, `rm`, `-` for piped stdin) turns argv into a `readermd://` URL (`Route.swift`) and hands it to the running/launched app via `NSWorkspace` (`Dispatch.swift`), which does the actual work, including any preference writes. The app is the single writer of its own preferences — the CLI never writes them, to avoid racing `AppState`'s in-memory `roots` re-persisting over a CLI write.

## Documentation

Three places describe the same features and drift when only one is touched (the
README and the site have both carried shortcuts that were plain wrong). The
`.keyboardShortcut` bindings in `ReaderMdApp.swift` are the authority for what a
key actually does — check them rather than copying an existing table.

- `Sources/ReaderMd/Resources/docs/` — `FAQ.md`, `SHORTCUTS.md`, `CHANGELOG.md`.
  Bundled into the app and opened from the Help menu, so they ship to users; the
  changelog also drives Sparkle's release notes (below).
- `docs/` — `features.md` (the one-line-per-feature list + shortcut tables),
  `install.md`, `cli.md`, `architecture.md`, `building.md`, and one page per
  feature area under `docs/features/` (`reading.md`, `library.md`, `git.md`, …)
  with screenshots in `docs/assets/screenshots/<slug>/`. `README.md` is only an
  index and highlights; detail belongs in `docs/`, not back in the README.
  `docs/markup-model.md` and `docs/superpowers/{specs,plans}` are working
  documents, not published pages.
- `web/src/data/content.ts` — landing-page copy only (highlight cards, the
  compact shortcut strip). The `/docs/` pages are **not** mirrored: the site
  renders `docs/*.md` and `docs/features/*.md` directly, so the markdown is the
  only copy of that prose. See `web/CLAUDE.md`.

Each `docs/features/<slug>.md` has a `<slug>.shots.json` manifest beside it —
plus `docs/hero.shots.json`, which has no page, because it captures the hero
image shared by the README and the landing page. A manifest describes every
screenshot: window size, prefs, the file to open, the actions to reach the
state. `.claude/skills/reader-docs` is the harness that captures them from the
running app (`scripts/capture.sh <manifest>`); follow that skill rather than
shooting screens by hand, and re-run the manifest after a UI change instead of
editing an image.

A user-visible change updates the bundled docs first, then `docs/`, then the
site data. `web/` is an Astro static site with its own `CLAUDE.md`, deployed by
Cloudflare Pages on a push to `main` that touches `web/` **or `docs/`** (both are
Pages build-watch paths, because the docs pages are built from `docs/` — see
`web/DEPLOYMENT.md`). So a docs or site edit that merges is live, with no
separate deploy step, and a Swift-only commit builds nothing.

## Conventions

- The app is **not sandboxed** — folder access is direct paths, no security-scoped bookmarks. The `WKWebView` gets broad `file://` read access so markdown-referenced local images resolve. All rendering assets are bundled; the only network access is Sparkle's auto-update check (fetching the appcast + update DMG).
- Any macOS 26-only API needs an availability guard with a pre-26 fallback (deployment target is 13).

## Auto-update (Sparkle)

`SPUStandardUpdaterController` (`ReaderMdApp.swift`) drives auto-update; it only starts in the packaged `.app` (gated on `SUFeedURL` in Info.plist) so `swift run` doesn't error. `make-app.sh` bundles `Sparkle.framework` into `Contents/Frameworks`, adds the `@executable_path/../Frameworks` rpath, and injects `SUFeedURL`/`SUPublicEDKey`. The feed is `releases/latest/download/appcast.xml` on GitHub, so the newest release's appcast is always served. `release.sh` signs the DMG (EdDSA private key in the login keychain), runs `generate_appcast`, and uploads the DMG + appcast to a `v<version>` GitHub release. **Release notes** come from the changelog, in three places: `release.sh` extracts the `## <version>` section of `Sources/ReaderMd/Resources/docs/CHANGELOG.md`, stages it beside the DMG as `Reader.md.md` (`generate_appcast` pairs release notes to an archive by basename), and passes `--embed-release-notes` so they land in the appcast as `<description sparkle:format="markdown">` — that's what Sparkle's update prompt shows. The same staged file is passed to `gh release create --notes-file`, so the GitHub release page reads the same as the prompt. And the same bundled changelog is what `AppState.checkWhatsNew()` opens on the first launch after an update. So the changelog entry must exist *before* the release: `release.sh` refuses to publish a version with no section, because all three would otherwise show the previous version's notes.

To cut a release: add the `## <version>` changelog entry, bump `CFBundleShortVersionString` (display) in `make-app.sh`, run `./make-app.sh`, then `./release.sh` (which refuses to publish if `CFBundleVersion` didn't increase past the published one, or if the changelog entry is missing). `release.sh` also rewrites `Casks/reader-md.rb` to the new version + DMG sha256 and commits it (`chore: update Homebrew cask to v<version>`), so the cask is not a manual step — but it is a commit to push. `CFBundleVersion` — the integer Sparkle actually compares — is derived from the build time (`date +%Y%m%d%H%M`) so it's always monotonic; no manual bump. Follow the `release` skill for the full checklist (changelog, About fallback, commit-before-tag). The binary is arm64-only, so updates are offered to Apple-silicon Macs only.
