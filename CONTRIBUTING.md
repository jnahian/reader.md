# Contributing to Reader.md

Thanks for your interest in improving Reader.md! This is a native macOS markdown
viewer built with SwiftUI/AppKit wrapping a single `WKWebView`. Contributions of
all sizes are welcome.

## Development setup

**Build toolchain:** Xcode 26 (or a Swift 6.2+ toolchain with the macOS 26 SDK).
This is required because the Liquid Glass `glassEffect` symbols only exist in
that SDK. The deployment target stays at macOS 13, so the built app still runs on
13+.

```bash
swift run                    # build and launch the app (unsandboxed)
swift build                  # compile only
swift build -c release       # release build
./make-app.sh                # assemble a double-clickable Reader.md.app
open "build/Reader.md.app"
```

`swift test` runs the `ReaderMdTests` target, which currently covers `fuzzyScore`
(the ⌘P quick-open ranker) — the app's one piece of pure, testable logic. Most of
the app is UI/WKWebView/FSEvents, so verify those changes by running the app.

## Architecture

The codebase is split into a native shell and web content pane. See
[`README.md`](README.md) and [`CLAUDE.md`](CLAUDE.md) for the full layout;
the short version:

- **Native shell** — `ContentView` + `Sources/ReaderMd/Views/` (native toolbar,
  sidebar, content, outline, find bar, quick-open).
- **Web content** — `MarkdownWebView` (`WKWebView`) renders markdown via bundled
  assets in `Sources/ReaderMd/Resources/web/` (marked, highlight.js, KaTeX,
  Mermaid, `bridge.js`).
- **`AppState`** — the single `@MainActor ObservableObject` source of truth,
  persisted to `UserDefaults`.

## Principles

- **KISS** — the simplest thing that works wins. No abstraction for a single use,
  no config for a value that never changes, no "flexibility" nobody asked for.
  Match the existing lean style; a smaller diff in the right place beats a clever one.
- **SOLID, pragmatically** — keep types focused and dependencies pointing at
  `AppState` (the single source of truth), but don't add protocols/interfaces for
  one implementation. This is a small app — apply SOLID where it removes real
  coupling, not as ceremony.
- **TDD where it pays** — for pure logic (rankers, parsers, formatters), write a
  failing test in `ReaderMdTests` first, then make it pass (`swift test`). UI /
  WKWebView / FSEvents code isn't unit-testable here — verify those by running the app.

## Conventions

- **Availability guards:** Any macOS 26-only API needs an availability check with
  a pre-26 fallback (`NSVisualEffectView` for glass). Deployment target is 13.
- **Imperative actions** (force reload, find next/prev, export, focus search) use
  the token-bump pattern on `AppState` (increment an `Int` token, react in a
  view's `.onChange`) rather than calling into the web view directly.
- **Swift ↔ JS bridge:** Swift → JS via `evaluateJavaScript` calling
  `window.ReaderMd.*`; JS → Swift via `WKScriptMessageHandler` message names.
- Match the surrounding code style — naming, comment density, and idiom.

## Submitting changes

1. Fork the repo and create a branch off `main`.
2. Make your change, keeping the diff focused on one thing.
3. Run the app (`swift run`) to confirm it works.
4. Open a pull request describing what changed and why.

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
