# `reader` CLI — design

**Date:** 2026-07-12
**Status:** approved, ready for implementation plan

## Goal

A `reader` command on the user's PATH that drives the running (or not-yet-running) Reader.md app:
open a markdown file, add a local folder as a root, add a remote (SSH) root, list roots, remove a root,
and open piped stdin.

## Non-goals

- No terminal markdown renderer (`--print` as ANSI output). `glow`/`bat` already do that, and it shares
  nothing with the app. `reader -` pipes stdin *into the app*.
- No scripting API. The CLI is fire-and-forget and eventually consistent (see "Consistency" below).
- No new IPC machinery (XPC, sockets).

## Architecture

### Transport — the `readermd://` URL scheme

The **app remains the single writer** of `UserDefaults`. The CLI never writes prefs; it dispatches a URL
and the app performs the mutation and persists it. This dodges the clobber race that a direct-write CLI
would hit whenever the app is running and later persists its in-memory `roots`.

Custom-scheme URLs are delivered to an already-running app through `.onOpenURL` (unlike
`open --args`, whose arguments a running app never sees), and launch the app if it is not running. One
mechanism covers both states.

| Command | URL dispatched |
|---|---|
| `reader notes.md` | `readermd://open?path=/abs/notes.md` |
| `reader .` , `reader ~/docs` | `readermd://add-folder?path=/abs/docs` |
| `reader remote me@vps:/srv/docs` | `readermd://add-remote?dest=me@vps&path=/srv/docs&name=docs` |
| `reader rm <path\|name>` | `readermd://remove?path=/abs/path` |
| `reader ls` | none — reads prefs directly |
| `cat x.md \| reader -` | writes a temp `.md`, then `readermd://open?path=…` |

All query values are percent-encoded by the CLI (`URLComponents`).

**App side.** `make-app.sh` adds `CFBundleURLTypes` declaring the `readermd` scheme.
`ReaderMdApp`'s existing `.onOpenURL` grows a router:

- `url.isFileURL` → today's behaviour, unchanged (Finder open).
- `readermd://` → parse the host as the verb, dispatch to `AppState`:
  `open` → `openPath`, `add-folder` → the public folder-add path, `add-remote` → see below,
  `remove` → `removeRoot`.
- Unknown verb or missing/invalid params → ignored.

`AppState.addRoot(_:persist:)` is currently private; expose a public entry point for the router rather
than widening `addRoot` itself.

### Security — only `add-remote` is gated

Any web page can fire a `readermd://` link. Three of the four verbs are harmless: they add, remove, or
select an entry in a sidebar, and touch nothing outside the user's own disk. `add-remote` is different —
it causes `rsync` over ssh with the user's `~/.ssh` keys.

So `add-remote` **arriving from a URL** opens the **prefilled Add Remote sheet** for confirmation
instead of syncing silently. The CLI's remote command therefore ends in a visible sheet the user
accepts; a drive-by URL from a web page ends in a sheet the user closes.

### The CLI binary

A second SwiftPM executable target (product `reader`), a single Swift file, no dependencies. Built by
`swift build`; `make-app.sh` copies it to `Contents/MacOS/reader` alongside the app executable.

The entry point is `@main` in `ReaderCLI.swift` — *not* top-level code in `main.swift`, which SwiftPM
cannot `@testable import` from a test target. This is what makes the pure logic below testable.

- **Path resolution** — relative paths are made absolute against the cwd, `~` expanded, symlinks
  resolved. A file → `open`; a directory → `add-folder`; a path that does not exist → message on stderr,
  exit 1.
- **`ls`** — reads `reader.md.folders` (string array) and `reader.md.remotes` (JSON blob) from the
  `com.nahian.reader-md` domain. Remotes are decoded with `JSONSerialization` into dictionaries, so the
  `RemoteSpec` struct is not duplicated in the CLI. Prints one root per line; remote roots are tagged
  with their `user@host:/path`.

  **The domain must be named explicitly** — `CFPreferencesCopyAppValue(key, "com.nahian.reader-md")`,
  not `UserDefaults.standard`. Inside the packaged `.app`, `Bundle.main` resolves to the app and
  `.standard` would happen to be right; run from `.build/debug/reader` there is no enclosing bundle and
  `.standard` silently reads a *different, empty* domain. Naming the domain is correct in both.

- **`rm <path|name>`** — matches a root by absolute path, or by root/remote name when no path matches.
  Dispatches `remove`; the app is still the writer.
- **stdin (`-`)** — reads stdin, writes it to
  `~/Library/Caches/com.nahian.reader-md/stdin/<epoch>.md`, opens that path. The `.md` extension is
  required or the app will not render it as markdown. The CLI cannot delete the file before the app has
  read it, so ownership of cleanup sits with the CLI: on each run it reaps stdin temps older than one
  day.
- **`reader` with no args** — usage on stdout, exit 0.

### Consistency

`reader add X` dispatches a URL and returns immediately; the app handles it and persists asynchronously.
`reader add X && reader ls` may therefore not list `X` yet. This is acceptable for an interactive tool
and is documented; no read-after-write guarantee is offered.

## Install

- **Homebrew** — the cask gains
  `binary "#{appdir}/Reader.md.app/Contents/MacOS/reader"`. Brew symlinks it into its prefix on install.
- **DMG users** — a **File → Install `reader` Command Line Tool** menu item symlinks the bundled binary
  into `/usr/local/bin/reader`, creating the directory if needed. If that is not writable, an alert shows
  the manual `ln -s …` line to run instead. No admin escalation, no privileged helper.

## Verification

- **`swift test`** covers the CLI's pure logic, which is where the bugs are: argument → URL mapping,
  path resolution (relative, `~`, trailing slash, missing file), percent-encoding of paths with spaces
  and `&`, and parsing of `user@host:/path` (including malformed input).
- **By hand** (the IPC path, and the check that catches the prefs-domain bug): build the `.app`, add a
  folder through the GUI, then run `/Applications/Reader.md.app/Contents/MacOS/reader ls` and confirm it
  lists that folder. Then `reader ~/some/dir` with the app running, and again with it closed.

## Files touched

- `Sources/ReaderCLI/ReaderCLI.swift` — new, the whole CLI.
- `Package.swift` — new executable target + product.
- `Sources/ReaderMd/ReaderMdApp.swift` — URL router in `.onOpenURL`; "Install CLI" menu item.
- `Sources/ReaderMd/Models/AppState.swift` — public entry points for add-folder / add-remote-sheet / remove.
- `make-app.sh` — `CFBundleURLTypes`; copy `reader` into `Contents/MacOS`.
- `Casks/reader-md.rb` — `binary` stanza.
- `Tests/ReaderMdTests/` — CLI logic tests.
- `README.md` — CLI section.
