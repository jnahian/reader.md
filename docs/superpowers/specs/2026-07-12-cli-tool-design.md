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
| `reader .` , `reader ~/docs` | `readermd://open?path=/abs/docs` |
| `reader remote me@vps:/srv/docs` | `readermd://add-remote?dest=me@vps&path=/srv/docs&name=docs` |
| `reader rm <path\|name>` | `readermd://remove?match=<token>` |
| `reader ls` | none — reads prefs directly |
| `cat x.md \| reader -` | writes a temp `.md`, then `readermd://open?path=…` |

All query values are percent-encoded by the CLI (`URLComponents`).

**One verb for files and folders.** `AppState.openDropped(_:)` already does exactly the routing the CLI
needs — directory → add as root, markdown file → open, anything else → ignore — and it already validates
the extension against `FileScanner.markdownExtensions`. The router reuses it, so:

- there is no separate `add-folder` verb, and
- `readermd://open?path=/etc/passwd` from a hostile web page is rejected, where a naive call to
  `AppState.openPath` (which does *not* check the extension) would have rendered it.

No new public `AppState` API is needed for open/add.

**Removal takes a token, not a path.** A remote root's `url` is its opaque
`~/Library/Application Support/Reader.md/remotes/<UUID>` cache directory — not something a user can
type. So `remove` carries the raw token the user typed and the **app** matches it against its in-memory
roots (absolute path first, then root/remote name), then calls `removeRoot`. Matching lives app-side
because that is where the names and the `RootFolder` values already are; the CLI stays dumb.

**App side.** `make-app.sh` adds `CFBundleURLTypes` declaring the `readermd` scheme.
`ReaderMdApp`'s existing `.onOpenURL` grows a router:

- `url.isFileURL` → today's behaviour, unchanged (Finder open).
- `readermd://` → the host is the verb: `open` → `openDropped`, `add-remote` → see below,
  `remove` → match token → `removeRoot`.
- Unknown verb, missing params, or a path that does not exist → ignored.

### Security — only `add-remote` is gated

Any web page can fire a `readermd://` link. Of the three verbs, `open` and `remove` are harmless: they
add, select, or un-list an entry in a sidebar, and touch nothing outside the user's own disk — `remove`
in particular never deletes anything, it only drops the root from the list. `add-remote` is different:
it causes `rsync` over ssh with the user's `~/.ssh` keys.

So `add-remote` **arriving from a URL** opens the **prefilled Add Remote sheet** for confirmation
instead of syncing silently. The CLI's remote command therefore ends in a visible sheet the user
accepts; a drive-by URL from a web page ends in a sheet the user closes.

`SidebarView` already presents that sheet on `state.showAddRemote` (a `Bool`), which has nowhere to
carry a prefill. Add a `pendingRemote: RemoteSpec?` to `AppState`: the router sets it and flips
`showAddRemote`; the sheet seeds its fields from it when non-nil and clears it on dismiss. The sidebar's
own **Add Remote** button leaves it `nil` and behaves exactly as it does today.

### Dispatch — target the app you came from

The CLI does **not** shell out to `/usr/bin/open`, and does not rely on Launch Services choosing the
right handler. With a `build/Reader.md.app` and an `/Applications/Reader.md.app` both registered, a bare
`readermd://` URL can be routed to the stale one.

The CLI binary lives *inside* the bundle, so `Bundle.main.bundleURL` **is** its own app. It dispatches
with `NSWorkspace.openURLs(_:withApplicationAt:configuration:)` against that bundle — the app you
invoked is the app that answers, and the scheme need not even be registered for this path to work. If
the binary is running outside any bundle (dev builds from `.build/`), it falls back to
`NSWorkspace.open(url)`; if that also fails, it reports that Reader.md could not be found and exits 1.

### The CLI binary

A second SwiftPM executable target (product `reader`), a single Swift file, no dependencies. Built by
`swift build`; `make-app.sh` copies it to `Contents/MacOS/reader` alongside the app executable.

The entry point is `@main` in `ReaderCLI.swift` — *not* top-level code in `main.swift`, which SwiftPM
cannot `@testable import` from a test target. This is what makes the pure logic below testable.

- **Path resolution** — relative paths are made absolute against the cwd, `~` expanded, symlinks
  resolved. The result is sent as `open`, and the app decides file-vs-folder. The CLI still validates
  locally first so the user gets feedback instead of silence: a path that does not exist, or a file
  whose extension is not markdown, is a message on stderr and exit 1. (The app re-checks anyway — it
  must, since URLs also arrive from elsewhere.)
- **`ls`** — reads `reader.md.folders` (string array) and `reader.md.remotes` (JSON blob) from the
  `com.nahian.reader-md` domain. Remotes are decoded with `JSONSerialization` into dictionaries, so the
  `RemoteSpec` struct is not duplicated in the CLI. Prints one root per line; remote roots are tagged
  with their `user@host:/path`.

  **The domain must be named explicitly** — `CFPreferencesCopyAppValue(key, "com.nahian.reader-md")`,
  not `UserDefaults.standard`. Inside the packaged `.app`, `Bundle.main` resolves to the app and
  `.standard` would happen to be right; run from `.build/debug/reader` there is no enclosing bundle and
  `.standard` silently reads a *different, empty* domain. Naming the domain is correct in both.

  **And it must synchronize first** — `CFPreferencesAppSynchronize("com.nahian.reader-md")` before the
  read. `cfprefsd` hands each process a cached snapshot; without this a freshly spawned `reader ls` can
  miss a value the app wrote moments ago.

- **`rm <token>`** — passes the token through to the app, which does the matching (see above). The CLI
  does not resolve it, so it needs no knowledge of how remote roots are named or where they cache.
- **stdin (`-`)** — reads stdin, writes it to
  `~/Library/Caches/com.nahian.reader-md/stdin/<epoch>.md`, opens that path. The `.md` extension is
  required or the app will not render it as markdown. The CLI cannot delete the file before the app has
  read it, so ownership of cleanup sits with the CLI: on each run it reaps stdin temps older than one
  day.
- **`reader` with no args** — usage on stdout, exit 0.

### Consistency

`reader ~/docs` dispatches a URL and returns immediately; the app handles it and persists asynchronously.
`reader ~/docs && reader ls` may therefore not list it yet. This is acceptable for an interactive tool
and is documented; no read-after-write guarantee is offered.

## Install

- **Homebrew** — the cask gains
  `binary "#{appdir}/Reader.md.app/Contents/MacOS/reader"`. Brew symlinks it into its prefix
  (`/opt/homebrew/bin` on Apple silicon) on install, and removes it on uninstall. Nothing else to do.

- **DMG users** — a **File → Install `reader` Command Line Tool** menu item. It attempts a plain symlink
  into `/usr/local/bin/reader` and, when that fails, shows an alert with the exact `sudo ln -s …` command
  and a **Copy** button.

  The failure path is the *normal* one, not an edge case: `/usr/local/bin` is `root:wheel` `drwxr-xr-x` on
  a stock macOS install, so an unprivileged symlink there fails with `EACCES`. The direct attempt only
  succeeds on machines where the user already owns the directory (typically Intel-Homebrew boxes). The app
  does **not** escalate — no `osascript … with administrator privileges`, no privileged helper, no
  `SMJobBless`. Handing the user one line to paste is a smaller and more honest thing than an app that
  asks for root to make a symlink.

  If `/usr/local/bin/reader` already exists (e.g. a previous install), the alert says so rather than
  clobbering it.

**Quarantine caveat.** A DMG dragged to `/Applications` carries `com.apple.quarantine`, and the app is
only ad-hoc signed. The first launch of the *app* (right-click → Open) clears it for the bundle, which
covers the nested `reader` binary too. Homebrew strips quarantine on cask install, so brew users never
see this. The README's CLI section says to launch the app once before using the CLI.

## Verification

- **`swift test`** covers the CLI's pure logic, which is where the bugs are: argument → URL mapping,
  path resolution (relative, `~`, trailing slash, missing file), percent-encoding of paths with spaces
  and `&`, and parsing of `user@host:/path` (including malformed input).
  (`@testable import` of an executable target is already how every existing test in `ReaderMdTests`
  works, so this carries no toolchain risk.)

- **By hand** — the parts no unit test reaches:
  1. Build the `.app`, add a folder through the GUI, then run
     `/Applications/Reader.md.app/Contents/MacOS/reader ls`. It must list that folder. *This is the check
     that catches the prefs-domain and `cfprefsd`-cache bugs; a test run under `swift run` would not.*
  2. `reader ~/some/dir` with the app running, and again with it closed.
  3. With both a `build/Reader.md.app` and an installed copy present, confirm the CLI's URL lands in the
     app it was invoked from — not the other one.
  4. `codesign -vvv --deep --strict` on the bundle after `make-app.sh`: `reader` is a second Mach-O in
     `Contents/MacOS`, i.e. nested code that must be sealed, not treated as a resource.
  5. `echo '# hi' | reader -` renders, and the temp file lands in the cache dir with a `.md` extension.

## Files touched

- `Sources/ReaderCLI/ReaderCLI.swift` — new, the whole CLI (`@main`).
- `Package.swift` — new executable target + `reader` product.
- `Sources/ReaderMd/ReaderMdApp.swift` — `readermd://` router in `.onOpenURL`; "Install CLI" menu item.
- `Sources/ReaderMd/Models/AppState.swift` — `removeRoot(matching:)` (token → root) and prefilling the
  Add Remote sheet from a URL. `openDropped` is reused as-is.
- `make-app.sh` — `CFBundleURLTypes`; copy `reader` into `Contents/MacOS` before signing.
- `Casks/reader-md.rb` — `binary` stanza.
- `Tests/ReaderMdTests/` — CLI logic tests.
- `README.md` — CLI section (including "launch the app once first").
