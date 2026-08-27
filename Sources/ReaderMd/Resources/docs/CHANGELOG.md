# Changelog

All notable changes to Reader.md are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Focus mode** (⌥⌘F) — hides the sidebar, outline and toolbar, goes
  fullscreen, and dims every section but the one you're reading. Each of the
  four pieces can be switched off in Settings; ⎋ or ⌥⌘F leaves, and so does
  leaving fullscreen any other way — the green traffic-light button. The hidden
  toolbar slides back on a top-edge hover, or on ⌘F, without leaving the mode.
  Settings also sets how wide the lit region is — every heading, or only
  headings down to H3, H2 or H1, so a section keeps its subsections lit — and
  how far the rest dims.

## [1.18.2] - 2026-08-26

### Fixed

- **Tooltips no longer appear on their own, or name the wrong control.** A
  tooltip asked the system for the part of its control still on screen and was
  answered with the whole sidebar or toolbar, so a pointer resting anywhere in
  that panel counted as resting on every control in it. Opening a file relaid
  the panel out and put up to five unrelated bubbles on screen at once, and
  pointing at a file in the sidebar named the × beside it instead of the file,
  whose own tooltip never arrived. A bubble now belongs to the control actually
  under the pointer.

## [1.18.1] - 2026-08-16

### Changed

- **The update prompt's dismiss button now reads "Remind Later"** instead of
  "Remind Me Later". Other languages keep their own wording.

### Fixed

- **Check for Updates… can't be left doing nothing.** Sparkle drops the request
  whenever it still believes it's showing an update whose window is already
  gone, and says so only in the system log — so the menu item would have
  answered a click with no window and no error. **Reader.md → Check for
  Updates…** now recognises that state and starts over rather than letting the
  click fall through.

## [1.18.0] - 2026-08-13

### Added

- **Links in the About panel** — **Website**, **Docs**, and **Report an Issue**,
  clickable straight from **Reader.md ▸ About Reader.md**. The Help menu carries
  the same destinations, with **Reader.md Website** and **Documentation** joining
  the two GitHub items already there.

### Fixed

- **No more tooltip on launch, or on switching back to Reader.md.** A window
  that opened under a stationary pointer counted as a hover, so whichever
  control happened to land under the cursor — usually the toolbar's sidebar
  toggle — put its bubble on screen unprompted, and ⌘-tabbing back with the
  pointer parked did it again. A bubble now waits for the pointer to actually be
  moved onto a control.
- **Git badges on a folder reached through a symlink** — a repository added as
  `/tmp/notes`, or through a link to another volume, showed no `M` · `A` · `?`
  badges at all. The sidebar looks them up under the resolved path the folder
  scan returns, and the badge map was keyed only under the path you added.
- **`reader ls` printed nothing useful for a cloned repository** — just a bare
  `:` where its origin should be. Cloned remotes arrived after that listing was
  written and never reached it; it now shows the clone URL.
- **`brew uninstall --zap` left your annotations behind.** Highlights, notes,
  and cached remote folders live under the app's name rather than its bundle
  id, and only the bundle-id paths were being removed — so a zap reported
  success and cleaned up nothing of yours.

## [1.17.0] - 2026-08-12

### Added

- **Settings window (⌘,)** — appearance, reading theme, text size, canvas width,
  the external editor, and the default PDF export layout in one place. Mostly a
  second way into preferences the toolbar and menus already carry; the default
  PDF layout, clearing the external editor, and picking an appearance mode
  directly rather than cycling to it live only here.
- **Clear the external editor** from Settings. Previously the only way to unset
  one was to uninstall it.
- **Settings in Quick Open** — type `>settings` in the ⌘P palette to open the
  window, alongside every other preference the palette already offered.

### Changed

- **The Layout popup in the ⌘E save panel is now a per-export choice.** It used
  to overwrite your default, so exporting once as Continuous quietly changed
  every later export. The default now lives in Settings ▸ Editing & Export.

### Fixed

- **⌘↩ and ⇧⌘↩ step through find matches**, as the search field's tooltips and
  the shortcuts page have always said. Neither was actually wired up; only
  plain ↩ moved to the next match.

## [1.16.1] - 2026-08-11

### Fixed

- **The × on a Favorites row works again**, as does dragging one to reorder. The
  row's tooltip covered it with an invisible layer that swallowed the click, so
  unpinning did nothing and the row wouldn't move. Recents was unaffected, which
  is why only Favorites looked stuck.
- **Sidebar × tooltips no longer get crossed.** Removing the last file from
  Recents or Favorites collapses that whole section, so the row beneath slid up
  under a pointer that never moved and kept the vanished row's label — which is
  how a Favorites × came to read "Remove from Recents". The row under the pointer
  is now re-checked whenever the sidebar re-lays out.

## [1.16.0] - 2026-08-11

### Added

- **Page-by-page PDF export.** The ⌘E save dialog now has a Layout control:
  **Page by Page** (the default) paginates the document onto real pages at your
  system paper size, with diagrams and images kept whole across page breaks,
  long code lines wrapped rather than cut off at the page edge, and the page
  painted in the reading theme's color; **Continuous** keeps the old single long
  page. Links stay clickable either way. Your last choice is remembered.
- **Step find matches from the toolbar.** The find field now has up/down chevrons
  beside the "N of M" count that jump to the previous/next match, and ⌘↩ / ⇧⌘↩
  step the matches as aliases for ⌘G / ⇧⌘G — so you can walk the results without
  leaving the search field or moving your hands.
- **Favorites in the sidebar.** Pin the files you keep coming back to and they
  sit in a **FAVORITES** section between Recents and your folders, in the order
  you arranged them — drag to reorder, hover **×** to unpin. Star a file from its
  hover control in the tree, from any file's context menu (tree, Recents, or
  filter results), with ⌘D for the open document, or from the ⌘P palette. Recents
  churns as you read; Favorites stay until you remove them, and a pinned file
  drops out of Recents so opening it never looks like it left the list. The bundled help
  pages and piped `reader -` documents aren't pinnable, the same way they stay
  out of Recents.

### Changed

- **Canvas width has its own topbar button.** The width picker (formerly
  "Column Width") moved out of the text-size menu into a dedicated ↔ button,
  and is now called **Canvas Width** everywhere. Wide is the new default for
  fresh installs; an existing choice is kept.
- **Picking what to diff against is a popover now.** The topbar's scope control
  replaces its pull-down menu. It names the current scope on the button, groups the branches under
  their own scrolling section, filters them by name in repos with many
  branches, and opens scrolled to the branch you're comparing against.

### Fixed

- **Opening a folder no longer shows a blank pane.** File-URL opens
  (`open -a Reader.md.app ~/docs`, dropping a folder on the app icon, `reader open`)
  and Recents taps now route directories into the sidebar as roots the same way
  **Add Folder** does, instead of treating them as markdown documents — and the
  sidebar reveals itself if it was collapsed. Stale folder paths already in Recents
  or Favorites are dropped on launch, and a folder can no longer be pinned.
- **Links to files with spaces in the name open again.** A relative link such as
  `[notes](<My Note.md>)` reaches the app percent-encoded; it now resolves to the
  real file instead of opening an empty document.
- **Tooltips no longer stay on screen after you click.** A hover bubble hung
  around once the click landed — and one that opened a menu or popover could
  strand it there entirely. Clicking now dismisses it.

## [1.15.0] - 2026-08-01

### Added

- **Clone a git repository as a folder.** The Add Remote sheet now offers **Git**
  alongside SSH: paste a clone URL and Reader.md clones it read-only into a local
  cache, fast-forwarding it on every launch the same way SSH folders re-sync. It
  uses your existing git credentials and never prompts, so a repository you can't
  authenticate to fails with git's own message instead of hanging.
- **Diff against a branch.** The diff scope control is now a menu, and below
  Unstaged / Staged / All it lists the repository's branches. Picking one
  compares your working copy — uncommitted edits included — against that
  branch's tip, which is the view for "what does this doc branch actually
  change?".
- **Hand a file to your editor with ⇧⌘E.** Reader.md stays a reader, but editing
  is now one keystroke away. Pick your editor once — **File → Set Default
  Editor…**, or right-click any file → **Always Open With** — and from then on
  the menu reads *Open in Zed* (or whichever you chose) and ⇧⌘E sends the open
  document straight there. Also in the sidebar context menus and the ⌘P palette.
  Reader.md re-renders the moment you save, so your editor on one side and
  Reader.md on the other reads like a live preview. Files with nothing to edit —
  the built-in help docs, piped `reader -` documents, and read-only remote
  folders — don't offer it.
- **An appearance mode that follows macOS.** The toolbar button now cycles
  Light → Dark → System, and in System mode Reader.md switches the moment macOS
  does — including on a schedule, without touching the app. New installs start
  in System. The button's icon now shows the mode you're *in* rather than the
  one you'd switch to, since three states don't fit "next mode", and the ⌘P
  palette names the mode you'd move to.

### Changed

- Folders inside a git repository no longer list files that `.gitignore` covers,
  so vendored and generated markdown stays out of the sidebar the way
  `node_modules` always has.

### Fixed

- A tooltip already showing under the pointer kept its old text when the button
  beneath it changed label — clicking the appearance button left the previous
  mode's tooltip on screen until you moved away and came back. It now re-renders
  in place.

## [1.14.1] - 2026-07-29

### Fixed

- The floating × that closes the document sat on top of a fullscreen Mermaid
  diagram, overlapping its controls in the top-right corner. It now steps aside
  while a diagram is fullscreen, and comes back when you leave.

## [1.14.0] - 2026-07-29

### Added

- **See what changed with ⇧⌘D.** When a markdown file lives in a git repository,
  Reader.md can swap the rendered page for a side-by-side source diff. A word or
  two edited in a long paragraph is highlighted on its own, so a small change no
  longer paints the whole paragraph red and green. The button appears in the
  toolbar only for files inside a repository.
- **Choose what you're comparing against.** The diff header carries an
  `Unstaged | Staged | All` control, so you can read just your unstaged edits,
  just what you've staged, or everything since the last commit. Your choice is
  remembered.
- **The outline becomes a hunk navigator.** In diff mode the outline lists one
  row per changed block, labelled with the heading it sits under and its
  `+3 −2` counts — click one to jump straight to it.
- **Changed files are marked in the sidebar.** Modified, added, untracked, and
  conflicted markdown files carry a small `M` / `A` / `?` / `U` badge.
- **Zoom into Mermaid diagrams.** Diagrams no longer have to fit the column
  width to be readable. Hover one for zoom controls, pinch or ⌘-scroll to zoom,
  drag to pan, or open it fullscreen — it stays sharp at any size. ⌘E always exports the
  diagram at its fitted size.

### Changed

- **The sidebar keeps up with large folders.** Scrolling a document, typing in
  the filter, and opening Quick Open no longer redraw the whole file tree. With
  a few thousand markdown files across several folders, scrolling was visibly
  busy and each keystroke in the filter rebuilt every row.
- **Filtering the sidebar shows a flat list of results.** Each hit is its
  filename over the folder it lives in (`notes › docs › api`), rather than the
  matching branches of the tree — so a filter over thousands of files stays
  instant, and `README.md` tells you which one it is.
- **Folders are scanned in the background.** Adding a large folder, or opening
  the app with several, no longer freezes the window while the tree is read;
  the sidebar fills in as each folder finishes.

### Fixed

- Task list items no longer show a bullet *and* a checkbox — the checkbox now
  sits in the marker column on its own, matching GitHub.

## [1.13.0] - 2026-07-22

### Added

- **Quick Open is now a command palette.** Start your query with `>` to run an
  app command — toggle the theme, sidebar, or outline, cycle the content width,
  add a folder, open a file, add a remote, or export/copy-path for the open
  document — without hunting through menus.
- **Jump to a heading with `#`.** Start your query with `#` to fuzzy-search the
  headings in the document you're reading and jump straight to one.
- Quick Open gained a footer with keyboard hints and a result count, and you can
  press ⌘1–⌘9 to open one of the first nine results directly.

### Changed

- **Quick Open matches across the whole path, and shows why.** ⌘P now fuzzy-matches
  your query against each file's full folder path, so `docsintro` finds
  `docs/intro.md` and typing a folder name scopes to the files under it. Results
  rank by match quality — a whole-filename hit beats the same letters scattered
  across a path — and the characters that matched are drawn bold in each row.

### Fixed

- **Quick Open showed the previous query's files.** Changing your search updated
  the result count but could leave the earlier query's rows on screen.

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

- **Highlight, annotate, and comment on what you read.** Select any text to
  highlight it in one of five colours, attach a note to it, or start a comment
  thread with replies and a **Resolve** button; the toolbar keeps a count of
  resolved threads, which doubles as a switch for hiding them. Marks are
  anchored to the words rather than to a position in the file, so an edit
  elsewhere leaves them where they were — and if the text one was made on
  disappears entirely, it is flagged as orphaned rather than quietly dropped.
  Nothing is written into your markdown: annotations live beside the file,
  keyed by its path, which is why renaming a file loses them.
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
