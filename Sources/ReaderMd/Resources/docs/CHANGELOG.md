# Changelog

## Unreleased

- **Find in Page** — highlights every match, shows a live "N of M" count, and
  steps through matches with ⌘G / ⇧⌘G or the find-bar chevrons. Reachable from
  the new topbar search button.
- **Find in Page moved to ⌘F**; **Filter Files (sidebar) moved to ⇧⌘F**.
- **Drag and drop now shows a drop target.** Dropping a file or folder onto the
  window always worked, but nothing highlighted while dragging, so it looked
  unsupported.
- Fixed: the find bar (⌘F) and quick-open (⌘P) fields now take keyboard focus
  immediately, instead of needing a click first.
- Fixed: the empty-state hints listed the wrong shortcuts — ⌘O opens a file (it
  does not add a folder), and the sidebar filter is ⇧⌘F.

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
