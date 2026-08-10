# PDF export: page-by-page and continuous layouts

**Date:** 2026-08-11
**Status:** Design approved, not implemented

## Summary

⌘E currently exports through `WKWebView.createPDF`, which produces a single
continuous PDF page the height of the whole document. Add a **Layout** choice to
the export save panel — **Page by Page** (paginated onto real paper-size pages)
or **Continuous** (today's behavior) — with page-by-page as the default and the
last choice remembered. Pagination comes from WebKit's own print engine via
`NSPrintOperation`; the continuous path is untouched.

## Goals

- Export a document as a normal multi-page PDF that prints and shares cleanly.
- Keep the continuous single-page export available.
- Zero extra clicks: the choice lives in the save panel the user already sees.
- Default to page-by-page; remember the last choice across exports and launches.

## Non-goals

- Headers, footers, or page numbers on paginated output.
- A paper-size or margin picker. Page-by-page uses the system default paper
  (`NSPrintInfo` — Letter or A4 by locale) with its default margins.
- Print CSS beyond the minimum: no widow/orphan tuning, no forced page breaks
  at headings.
- Exporting in diff mode (⌘E stays disabled there, as today).

## Design

### State

- `ExportLayout: String, CaseIterable` — `pageByPage`, `continuous` — declared
  in `Models/AppState.swift` beside `ContentWidth`, with a `displayName`.
- `Settings.loadExportLayout()` / `saveExportLayout(_:)` with key
  `reader.md.exportLayout`; the load falls back to `.pageByPage` when unset.
- No `@Published` property on `AppState`: nothing observes the value — it is
  read when the save panel opens and written when the user confirms. The
  coordinator (app code) is the only reader/writer, so the app remains the
  single writer of its own preferences.

### Save panel

`savePDF`'s `NSSavePanel` (in `MarkdownWebView.Coordinator`) gains an accessory
view: a labeled `NSPopUpButton` — "Layout: Page by Page / Continuous" —
preselected from `Settings.loadExportLayout()`. On OK the selection is saved
back before rendering. Plain AppKit, matching the panel it sits in; no
`NSHostingView` needed for one control.

### Flow

Order inverts from render-then-ask to ask-then-render, because the layout
choice happens in the panel:

1. ⌘E → `exportToken` bump → `exportPDF()` (unchanged trigger path).
2. Show the save panel with the accessory. Cancel ends here — `beforeExport()`
   has not run, so there is no state to restore.
3. `window.ReaderMd.beforeExport();` (clears find highlights and diagram zoom,
   as today), then render by layout:
   - **Continuous** — existing `createPDF` path; write the data to the chosen
     URL.
   - **Page by Page** — `webView.printOperation(with:)` using a fresh
     `NSPrintInfo` (which carries the system default paper size and margins),
     `jobDisposition = .save` with `.jobSavingURL` set to the chosen URL, both
     panels hidden. WKWebView print operations must be run with
     `runModal(for:delegate:didRun:contextInfo:)` against the app's window —
     a bare `run()` does not work for WKWebView — so the coordinator runs it
     that way and treats the delegate callback as completion.
4. `window.ReaderMd.afterExport();` on both success and failure, both paths.

### Backgrounds and theme

Paginated printing drops CSS backgrounds by default. Set
`WKPreferences.shouldPrintBackgrounds = true` so the export keeps the current
theme, matching what continuous export does. The API is macOS 13.3+ against our
13.0 deployment target, so it is set under `#available(macOS 13.3, *)`; on
13.0–13.2 paginated export prints content on white — accepted, not worked
around.

### Print CSS

A small `@media print` block in the bundled stylesheet:

- Neutralize the canvas width: the reading column's `max-width` and centering
  should not constrain the printed page — pages have their own width.
- `break-inside: avoid` on Mermaid diagram containers and images so they are
  not sawn in half at page boundaries. Code blocks and tables are allowed to
  break; a multi-page code block is normal.
- Hide interactive chrome that exists only on screen (diagram zoom controls),
  mirroring what `beforeExport()` already resets.

## Docs

- Bundled `FAQ.md`: the export answer describes the two layouts and the
  page-by-page default. `CHANGELOG.md` gains an Unreleased entry.
- `docs/features.md` export bullet mentions the layout choice.
- `web/src/data/content.ts` mirrors the feature copy.

## Testing

- Unit (`ReaderMdTests`): `Settings` export-layout round-trip and the
  `.pageByPage` fallback when the key is unset or garbage.
- Manual, per the project's UI-testing convention: export a long document
  containing code blocks, a wide table, images, and a Mermaid diagram in both
  layouts and both color themes; verify page breaks don't split diagrams or
  images, the theme background survives pagination (macOS 13.3+), continuous
  output is byte-for-byte the same flow as before, and cancelling the panel
  leaves the document state untouched.
