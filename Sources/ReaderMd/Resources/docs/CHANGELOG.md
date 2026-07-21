# Changelog

All notable changes to Reader.md are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.12.0] - 2026-07-21

### Changed

- **Quick Open searches every folder, and it's instant.** ⌘P used to sort the
  whole index by folder name and cut the list short, so a large first folder hid
  every other folder and server you'd added. It now searches all of them, and
  builds its index once when it opens instead of re-scanning your folders on
  every keystroke.
- **Quick Open matches like the sidebar.** Typing finds the same files the
  sidebar filter finds — any part of a filename, upper or lower case — instead
  of a looser fuzzy match that surfaced files you didn't mean.
- Opening ⌘P with an empty box lists the files you opened most recently; both
  that and search results show ten rows.

### Fixed

- **Quick Open's arrow keys.** Up and down now move through the results you're
  actually looking at, and Return opens the highlighted one. They previously
  walked the list as it was before you started typing.

## [1.11.0] - 2026-07-15

### Changed

- **Softer tooltips.** Hovering a button now shows a small rounded bubble that
  matches the app's chrome, in place of the yellow system tooltip.
- **The Standard theme now matches GitHub.** Standard adopts GitHub's exact
  colours for text, borders, and code, so it reads like github.com in both light
  and dark. The separate "GitHub" theme added in 1.10.0 is gone — Standard
  replaces it. If you had GitHub selected, you're moved to Standard automatically.

## [1.10.0] - 2026-07-14

### Added

- **Documents remember where you stopped.** Reopening a long file returns you to
  the place you left off instead of the top. A document you barely started, or
  one you finished, still opens at the top — resuming into the last screen of
  something you've already read is worse than not resuming.
- **A GitHub reading theme.** The content pane can now wear GitHub's palette,
  fonts, and code colours, alongside Standard, Editorial, and Terminal. Pick it
  from the toolbar's text menu.

## [1.9.0] - 2026-07-13

### Added

- **A close button on the open document** — a floating × in the top-right corner,
  the visible form of ⌘W.

### Changed

- **New sidebar shortcuts.** ⌘B toggles the file sidebar and ⇧⌘B the outline —
  the keys the rest of the Mac uses. (They were ⌘\ and ⇧⌘O.)
- **The empty screen is clickable.** Open a file, add a folder, quick-open, or
  jump to the sidebar filter by clicking the row instead of only reading about
  the shortcut.
- **The sidebar reveals what you open.** Opening a file from Quick Open, Recents,
  or a link in a document expands the folders down to it, instead of leaving it
  hidden in a collapsed tree.

### Fixed

- The × on a Recents row removes the entry from Recents again (it briefly closed
  the file instead). Closing lives on the document's own × and ⌘W.

## [1.8.0] - 2026-07-13

### Added

- **Full-width reading column.** The content column now has three widths —
  Narrow, Wide, and Full Width — instead of the old narrow/wide toggle. Full
  Width fills the window, so wide tables and code blocks stop scrolling
  sideways on a large display. Pick one from the toolbar's text menu or **View →
  Column Width**; ⇧⌘\ cycles them. If you had the wide column on, you stay on
  Wide.

## [1.7.1] - 2026-07-13

### Changed

- **You can close a document now.** ⌘W closes the open file and leaves the window
  up, rather than closing the window — which, with one window open, quit the app.
  Press it again with nothing open and Reader.md asks before quitting. **File →
  Close** does the same, and right-clicking the open file in the sidebar or in
  Recents offers **Close**. On the Recents row for the open file, the hover **×**
  closes it; removing the entry from Recents moved to that row's context menu.

### Fixed

- `reader` opened a new window on every invocation instead of reusing the
  window you already had open.

## [1.7.0] - 2026-07-12

### Added

- **A `reader` command line tool.** Open a file, add a folder, add a remote, or
  pipe markdown straight into the app from your terminal:

  ```
  reader notes.md                    open a markdown file
  reader .                           add the current directory to the sidebar
  reader remote me@vps:/srv/docs     add a remote (SSH) folder
  reader ls                          list your folders
  reader rm <name|path>              remove one
  git diff | reader -                open piped markdown
  ```

  It drives the app rather than replacing it — each command hands the work to
  Reader.md. `reader remote` opens the Add Remote sheet for confirmation rather
  than connecting behind your back.

  **Already installed with Homebrew?** Run `brew reinstall --cask reader-md`
  once to put `reader` on your PATH — an in-place update can't add it. If you
  installed from the DMG, use **File → Install reader Command Line Tool…**.
- **A website:** [reader-md.jnahian.me](https://reader-md.jnahian.me).

### Changed

- **Add Remote Folder… is now in the File menu**, so it's reachable with the
  sidebar collapsed. New shortcuts: **⇧⌘A** adds a folder, **⌥⌘A** adds a remote.
- **The window uses the native macOS toolbar**, so on macOS 26 it reads as real
  Liquid Glass and its controls group into capsules the way the system draws them.
- **Update prompts now show what changed** instead of a blank pane.

### Fixed

- The find field is disabled when no document is open, and ⌘F focuses it
  reliably.

## [1.6.0] - 2026-07-10

### Added

- **Find in Page** — highlights every match, shows a live "N of M" count, and
  steps through matches with ⌘G / ⇧⌘G or the find-bar chevrons. Reachable from
  the new topbar search button.
- **Reading themes** — pick Standard, Editorial, or Terminal from the text-size
  menu. Each brings its own typography, accent, and syntax highlighting, and the
  choice persists across launches.
- **Footnotes** render as a linked, styled section at the end of the document.
- **Install with Homebrew** — `brew tap jnahian/reader.md https://github.com/jnahian/reader.md`,
  then `brew install --cask reader-md`.

### Changed

- **Find in Page moved to ⌘F**; **Filter Files (sidebar) moved to ⇧⌘F**.
- **Links follow your macOS accent color.** In the Standard theme, links, heading
  anchors, and markers now use the accent color you picked in System Settings,
  updating live when you change it or switch light/dark. The Editorial and
  Terminal reading themes keep their own tuned accents.
- **The topbar follows macOS Preview** — the find bar now lives in the topbar
  rather than as a separate strip, and the controls have room to breathe.

### Fixed

- **Drag and drop now works, and shows a drop target.** Dropping a file or folder
  onto the reading pane never actually worked while a document was open — WebKit
  refused the drop — and nothing highlighted while dragging, so it looked
  unsupported. Both fixed; consecutive drops work too.
- The find bar (⌘F) and quick-open (⌘P) fields now take keyboard focus
  immediately, instead of needing a click first.
- The empty-state hints listed the wrong shortcuts — ⌘O opens a file (it does
  not add a folder), and the sidebar filter is ⇧⌘F.
- Opening the FAQ, shortcuts, or release notes from the Help menu no longer
  pushes them into your recent files.

## [1.5.0] - 2026-07-08

### Added

- **Remote (SSH) folders** — add a remote folder and Reader.md syncs it
  read-only to a local cache via rsync.
- **Help menu** — FAQ, keyboard-shortcut cheatsheet (⌘/), and release notes.

## [1.4.0] - 2026-07-08

### Added

- **Annotations** — highlight a selection and attach a note.
- **Comment threads** with resolve.
- **Liquid Glass topbar buttons** on macOS 26 (Tahoe).

### Fixed

- Markup popover UX fixes (positioning, alignment, click handling).

## [1.3.2] - 2026-07-07

### Added

- **Auto-update via Sparkle**, delivered as a DMG installer.
- **About panel** with version info.

### Changed

- Render YAML frontmatter as a table.

## [1.3.0] - 2026-07-07

### Added

- Reorder root folders by drag.

### Changed

- Hidden folders are scanned, so folders like `.github` show up.

## [1.2.0] - 2026-07-07

### Added

- Drop files onto the window body; manage recent files.

### Changed

- Root folders collapse in the sidebar by default.

## [1.1.0] - 2026-07-07

### Added

- Open single files, drag-and-drop, and register as the default markdown handler.

## [1.0.1] - 2026-07-07

### Fixed

- Sign the shared app; fix resource loading in the packaged bundle.

## [1.0.0] - 2026-07-06

### Added

- First release: native macOS markdown viewer with Mermaid, LaTeX, syntax
  highlighting, live reload, outline, quick open, and PDF export.
