# Changelog

## 1.8.0 — 2026-07-13

- **Full-width reading column.** The content column now has three widths —
  Narrow, Wide, and Full Width — instead of the old narrow/wide toggle. Full
  Width fills the window, so wide tables and code blocks stop scrolling
  sideways on a large display. Pick one from the toolbar's text menu or **View →
  Column Width**; ⇧⌘\ cycles them. If you had the wide column on, you stay on
  Wide.

## 1.7.1 — 2026-07-13

- **You can close a document now.** ⌘W closes the open file and leaves the window
  up, rather than closing the window — which, with one window open, quit the app.
  Press it again with nothing open and Reader.md asks before quitting. **File →
  Close** does the same, and right-clicking the open file in the sidebar or in
  Recents offers **Close**. On the Recents row for the open file, the hover **×**
  closes it; removing the entry from Recents moved to that row's context menu.
- Fixed: `reader` opened a new window on every invocation instead of reusing the
  window you already had open.

## 1.7.0 — 2026-07-12

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
- **Add Remote Folder… is now in the File menu**, so it's reachable with the
  sidebar collapsed. New shortcuts: **⇧⌘A** adds a folder, **⌥⌘A** adds a remote.
- **The window uses the native macOS toolbar**, so on macOS 26 it reads as real
  Liquid Glass and its controls group into capsules the way the system draws them.
- **Update prompts now show what changed** instead of a blank pane.
- **A website:** [reader-md.jnahian.me](https://reader-md.jnahian.me).
- Fixed: the find field is disabled when no document is open, and ⌘F focuses it
  reliably.

## 1.6.0 — 2026-07-10

- **Find in Page** — highlights every match, shows a live "N of M" count, and
  steps through matches with ⌘G / ⇧⌘G or the find-bar chevrons. Reachable from
  the new topbar search button.
- **Find in Page moved to ⌘F**; **Filter Files (sidebar) moved to ⇧⌘F**.
- **Reading themes** — pick Standard, Editorial, or Terminal from the text-size
  menu. Each brings its own typography, accent, and syntax highlighting, and the
  choice persists across launches.
- **Footnotes** render as a linked, styled section at the end of the document.
- **Links follow your macOS accent color.** In the Standard theme, links, heading
  anchors, and markers now use the accent color you picked in System Settings,
  updating live when you change it or switch light/dark. The Editorial and
  Terminal reading themes keep their own tuned accents.
- **The topbar follows macOS Preview** — the find bar now lives in the topbar
  rather than as a separate strip, and the controls have room to breathe.
- **Install with Homebrew** — `brew tap jnahian/reader.md https://github.com/jnahian/reader.md`,
  then `brew install --cask reader-md`.
- **Drag and drop now works, and shows a drop target.** Dropping a file or folder
  onto the reading pane never actually worked while a document was open — WebKit
  refused the drop — and nothing highlighted while dragging, so it looked
  unsupported. Both fixed; consecutive drops work too.
- Fixed: the find bar (⌘F) and quick-open (⌘P) fields now take keyboard focus
  immediately, instead of needing a click first.
- Fixed: the empty-state hints listed the wrong shortcuts — ⌘O opens a file (it
  does not add a folder), and the sidebar filter is ⇧⌘F.
- Fixed: opening the FAQ, shortcuts, or release notes from the Help menu no
  longer pushes them into your recent files.

## 1.5.0 — 2026-07-08

- **Remote (SSH) folders** — add a remote folder and Reader.md syncs it
  read-only to a local cache via rsync.
- **Help menu** — FAQ, keyboard-shortcut cheatsheet (⌘/), and release notes.

## 1.4.0 — 2026-07-08

- **Annotations** — highlight a selection and attach a note.
- **Comment threads** with resolve.
- **Liquid Glass topbar buttons** on macOS 26 (Tahoe).
- Markup popover UX fixes (positioning, alignment, click handling).

## 1.3.2 — 2026-07-07

- **Auto-update via Sparkle**, delivered as a DMG installer.
- Render YAML frontmatter as a table.
- **About panel** with version info.

## 1.3.0 — 2026-07-07

- Scan hidden folders; reorder root folders by drag.

## 1.2.0 — 2026-07-07

- Drop files onto the window body; manage recent files.
- Root folders collapse in the sidebar by default.

## 1.1.0 — 2026-07-07

- Open single files, drag-and-drop, and register as the default markdown handler.

## 1.0.1 — 2026-07-07

- Sign the shared app; fix resource loading in the packaged bundle.

## 1.0.0 — 2026-07-06

- First release: native macOS markdown viewer with Mermaid, LaTeX, syntax
  highlighting, live reload, outline, quick open, and PDF export.
