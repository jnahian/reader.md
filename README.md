# Reader.md (Swift / SwiftUI)

**Website:** [reader-md.jnahian.me](https://reader-md.jnahian.me)

A native macOS markdown viewer built with SwiftUI and AppKit. The whole shell —
toolbar, sidebar, file search, outline, folder management, file watching, and SF
Symbol icons — is native SwiftUI. The markdown content pane is a `WKWebView` that
renders through bundled JS engines, because Mermaid diagrams and LaTeX math have
no native equivalent.

## Highlights

- **Multi-folder browser** with ⌘P fuzzy quick-open across every root
- **Remote (SSH) folders** — `rsync`'d read-only from a VPS, reusing your `~/.ssh` config, storing no credentials
- **Mermaid, LaTeX, and syntax highlighting** from bundled engines — no network access
- **Live reload** — the open file re-renders with scroll preserved the moment it changes on disk
- **Hand off to your editor** with ⇧⌘E, which turns an editor beside Reader.md into a live preview
- **Liquid Glass chrome** on macOS 26, falling back to `NSVisualEffectView` on 13–15

## Install

```bash
brew tap jnahian/reader.md https://github.com/jnahian/reader.md
brew trust --cask jnahian/reader.md/reader.md
brew install --cask reader-md
```

Or download `Reader.md.dmg` from the
[latest release](https://github.com/jnahian/reader.md/releases/latest). macOS 13+,
Apple silicon. Full instructions — including clearing quarantine on a direct
download — are in [the install guide](docs/install.md).

## Documentation

| | |
|---|---|
| [Features & shortcuts](docs/features.md) | everything the app does, and the keys that do it |
| [Install](docs/install.md) | requirements, Homebrew, direct download, quarantine |
| [Command line](docs/cli.md) | the `reader` CLI |
| [Architecture](docs/architecture.md) | how the native shell and web pane fit together |
| [Building](docs/building.md) | run from source, package a `.app`, cut a release |
| [Changelog](Sources/ReaderMd/Resources/docs/CHANGELOG.md) | release history (also in-app, Help → Release Notes) |

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
conventions, and the PR flow. By participating you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) © Julkar Naen Nahian
