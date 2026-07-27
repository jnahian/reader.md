# GitHub-style diff mode for markdown files

**Date:** 2026-07-27
**Status:** Design approved, not implemented

## Summary

Add a diff view mode to Reader.md. When a markdown file lives in a git repo, a
toolbar toggle swaps the rendered content pane for a GitHub-style side-by-side
source diff of that file, with word-level intra-line highlighting. The sidebar
marks changed files with git status badges. The outline pane becomes a hunk
navigator.

## Goals

- See what changed in a markdown file without leaving the reader.
- Distinguish staged from unstaged changes.
- Read prose diffs — a one-word edit in a paragraph must not paint the whole
  paragraph red and green.

## Non-goals (v1)

Named so they read as deferred, not overlooked:

- A `reader diff` CLI verb.
- Comparison against an arbitrary ref, branch, or tag.
- Comparing two arbitrary files.
- A unified/split toggle. Split only.
- A rich rendered diff (rendered markdown with inline ins/del marks) — GitHub's
  "rich diff" toggle. The likeliest follow-on.

## Decisions

| Question | Decision |
|---|---|
| Diff against what | The git triad: working tree vs HEAD, plus staged vs unstaged |
| Render style | Split source diff, side by side |
| Entry point | Toolbar toggle, per file, plus git status badges in the sidebar |
| Scope control | 3-way segmented control in the diff header |
| Intra-line | Word-level highlighting, in v1 |
| Live in diff mode | Find in page, outline |
| Suppressed in diff mode | Marks, PDF export, word count, reading progress |
| Outline contents | One row per hunk, labelled by its enclosing heading |

## Architecture

### `Sources/ReaderMd/Models/GitDiff.swift` (new)

The entire git layer. No UI, no `AppState` reference. Roughly 150 lines plus
the word-diff helper.

```
GitDiff.repoRoot(for: URL) -> URL?
GitDiff.status(root: URL) -> [String: Status]
GitDiff.diff(file: URL, scope: DiffScope) -> DiffFile?
```

- `repoRoot` shells `git -C <dir> rev-parse --show-toplevel`.
- `status` shells `git status --porcelain`, keeping markdown paths only.
- `diff` shells `git diff` / `git diff --cached` / `git diff HEAD` per scope and
  parses the unified output.

`DiffScope` is `.unstaged | .staged | .all`.

`DiffFile` is a plain struct carrying `[Hunk]`. Each `Hunk` holds its old and new
line ranges, its paired rows, its `+`/`−` counts, and the markdown heading it
falls under — found by walking backwards from the hunk's start through the old
file's `#` lines. Each row that is a paired replacement also carries word-level
insert/delete spans for both sides.

**Why parsing lives in Swift, not JS.** Unified-diff parsing and word-level LCS
are pure logic, so they land in the existing `ReaderMdTests` target against
fixture strings — the only part of this feature testable without running the app.
It also means the hunk-to-heading outline is computed once in Swift and assigned
straight to `state.outline`, with no JS round trip.

### `bridge.js`

Gains `window.ReaderMd.loadDiff(json)`, which builds the split table DOM from the
parsed model. Swift to JS only; no new `WKScriptMessageHandler` message names.

### `AppState`

Two new persisted properties, saved to `UserDefaults` alongside the other view
preferences:

- `diffMode: Bool`
- `diffScope: DiffScope`

This is a **view mode, not a one-shot**, so it does not use the token-bump
pattern. `MarkdownWebView.updateNSView` branches on `diffMode` and calls
`loadDiff` instead of `loadMarkdown`.

`diffMode` is sticky: it survives switching files and relaunching the app, so
the app can launch in diff mode. Two consequences to get right:

- Selecting a **tracked file with no changes in the current scope** shows the
  per-scope empty state, not a silent fallback to rendered view. The toggle's
  position matches what you see.
- Selecting a **file with no repo at all** (remote folder, stdin doc, loose file)
  renders normally, since the toggle is hidden there and there is nothing to
  diff. `diffMode` stays set, so returning to a repo file resumes the diff.

### Refresh

The existing `FolderWatcher` → `reloadToken` path recomputes the diff rather than
re-rendering the markdown.

One gap this leaves: staging a file does not touch the working tree, and `.git`
is in `FileScanner.ignoredDirs`, so FSEvents never fires for it. Also recompute
on `NSApplication.didBecomeActiveNotification`, which covers staging something in
a terminal and switching back.

### Concurrency

Every `git` invocation runs off the main actor via `Process`, with the result
hopped back to `AppState`. A cold `git diff` on a large repo is tens of
milliseconds, but it never blocks the UI.

## UI

### Toolbar toggle

One button in the existing toolbar, following the glass-capsule grouping
convention, with a keyboard shortcut and a quick-open command entry. Three
states:

- **Hidden** when the file is not in a git repo — remote folders, stdin docs,
  loose files opened via `reader open`. Nothing to explain, nothing to click.
- **Disabled** with a tooltip when the file is tracked but unchanged.
- **Active toggle** otherwise.

Git availability is probed once at launch and cached. If git is absent the button
never appears.

**Known wart:** on a Mac without Command Line Tools, that first probe can pop
Apple's CLT install dialog, because `/usr/bin/git` is an `xcode-select` shim.
Once, at startup, and only on machines with no git at all. Accepted.

### Diff pane

Replaces the rendered content. Header row carries the segmented
`Unstaged | Staged | All` control, the filename, and the `+12 −4` totals.

Below it, the split table: old lines left, new right, line numbers in gutters,
red and green row backgrounds, unchanged context between changes. Context between
distant hunks is collapsed and expandable, as GitHub does with `⋯`.

The sidebar stays where it is. The split table scrolls horizontally inside its own
container rather than squeezing. Long lines wrap within their cell — for prose
that reads better than horizontal scroll.

### Word-level highlighting

Within a paired replacement row, the words that actually changed get a stronger
background than the row itself. Computed by a word-level LCS in `GitDiff.swift`,
emitted as character spans on the row model, applied as `<span>` wrappers by
`bridge.js`. Without this, a single-word edit in a paragraph paints the entire
paragraph, which is the common case for markdown prose.

### Sidebar badges

`git status --porcelain` runs on the repo root and refreshes on the same triggers
as the diff. Changed markdown files get a small colored letter after the name,
matching the sidebar's existing row density:

- `M` modified
- `A` added
- `U` conflicted
- `?` untracked

Roots that are not git repos get no badges.

### Outline in diff mode

The outline pane lists one row per hunk, labelled by the heading that hunk falls
under, with that hunk's `+`/`−` counts. Clicking scrolls to the hunk. In diff
mode the pane's job is jumping between changes, and this mirrors how GitHub labels
hunk headers.

```
OUTLINE
• Install            +3 −1
• Install › Homebrew +1 −1
• Configuration      +8 −0
• FAQ                +0 −2
```

### Suppressed in diff mode

- **Marks** — the mark layer hides and mark creation is disabled. Marks anchor by
  character offset into the rendered DOM via `resolveAnchor`; against diff rows
  they would land on the wrong text or orphan themselves.
- **Export PDF (⌘E)** — greyed out.
- **Word count and reading progress** — hidden.

Find in page (⌘F) and the outline stay live.

### Theming

Diff row and word-span colors are declared as CSS variables in `template.html`
next to the existing theme variables, defined for light, dark, and each reading
theme. Not hardcoded green and red, so sepia does not get neon rows.

## Edge cases

| Case | Behavior |
|---|---|
| Untracked file (`??`) | `git diff` returns nothing; fall back to `--no-index /dev/null <file>` so the whole file renders as added |
| Newly added or staged-new | Old side empty, all green |
| Renamed (`-M`) | Diff against the old path; header shows `old.md → new.md` |
| Conflicted (`U`) | Toggle appears, but the pane renders a "file has conflicts" notice instead of git's combined-diff format |
| Selected scope has no changes | Per-scope empty state — "No staged changes" — with the other scopes still clickable |
| Frontmatter | Shown as literal source lines. Diff mode is source; no `splitFrontmatter` stripping |
| Non-UTF8 bytes | Lossy decode, no crash |
| Very large diff | Rendered in full, no cap. Virtualization is a problem to solve if it ever shows up |

## Testing

`GitDiff.swift` is pure logic over strings, so `swift test` covers it:

- Unified-diff fixture text in, hunks / counts / enclosing heading / word spans out.
- Hunk-to-heading resolution: hunk under a nested heading, hunk before any
  heading, hunk spanning a heading change.
- Word-level LCS: whole-line replacement, single-word edit, leading and trailing
  whitespace, empty line, line added with no counterpart.
- Scope-to-argv mapping for the three `DiffScope` cases.

The `Process` invocation, the split table rendering, the sidebar badges, and the
diff-mode suppression of marks and export are verified by running the app, per
the repo's existing convention that UI and WKWebView behavior are not unit
tested.

## Files touched

| File | Change |
|---|---|
| `Sources/ReaderMd/Models/GitDiff.swift` | New. Git invocation, unified-diff parsing, word-level LCS, hunk-to-heading |
| `Sources/ReaderMd/Models/AppState.swift` | `diffMode`, `diffScope`, persistence, refresh triggers, outline swap |
| `Sources/ReaderMd/Models/FileNode.swift` | Carry git status per node for badges |
| `Sources/ReaderMd/Views/Toolbar.swift` | Diff toggle button |
| `Sources/ReaderMd/Views/MarkdownWebView.swift` | Branch on `diffMode`; call `loadDiff` |
| `Sources/ReaderMd/Views/FileTreeRow.swift` | Status badge |
| `Sources/ReaderMd/Views/TOCView.swift` | Hunk rows with counts |
| `Sources/ReaderMd/Views/QuickOpenView.swift` | Command entry for the toggle |
| `Sources/ReaderMd/Resources/web/bridge.js` | `loadDiff`, split table DOM, word spans |
| `Sources/ReaderMd/Resources/web/template.html` | Diff CSS variables per theme |
| `Tests/ReaderMdTests/` | `GitDiffTests.swift` |
