# Product Marketing Context

**Document version:** 1.0.0
**Last updated:** 2026-08-12
**Status:** Draft auto-generated from the repository. Sections marked
**[assumed]** were inferred from code and copy, not stated by the author, and
should be corrected. Sections marked **[unknown]** have no evidence in the repo
and were deliberately left empty rather than invented.

## Product Overview

**One-line:** A native macOS markdown viewer.

**What it does:** Reader.md renders local and remote markdown files in a native
Mac window — sidebar, outline, find, and toolbar are all SwiftUI and AppKit.
Only the content pane is a `WKWebView`, because Mermaid diagrams and LaTeX math
have no native equivalent. It watches files on disk and re-renders as they
change, so an editor beside it becomes a live preview.

**Category:** Markdown viewer / previewer for macOS. Adjacent shelves people
browse: markdown editors, note-taking apps, documentation tools.

**Product type:** Free, open-source (MIT) native desktop app.

**Business model:** No pricing. Distributed via Homebrew cask and a direct DMG,
updated in place by Sparkle. Not monetised; the return is GitHub stars,
contributors, and use. **[assumed]**

**Requirements:** macOS 13+, Apple silicon only (the binary is arm64).

## Target Audience

**Who:** Developers and technical writers on Apple-silicon Macs who *read* a lot
of markdown — repository docs, design specs, handbooks, notes — and want it to
look right without opening an editor or a browser. **[assumed]**

**Decision-maker:** The individual user. There is no purchase, no team rollout,
no procurement.

**Primary use case:** Read markdown that lives on disk — often inside a git
repository — with diagrams, math, and code rendered properly.

**Jobs to be done:**
1. "Show me this repo's docs the way they'll look, without leaving my Mac."
2. "Give me a live preview beside the editor I already use."
3. "Let me read markdown on a server I have SSH access to, without syncing it."

**Specific scenarios:**
- Reading a repository's `docs/` folder while working in it
- Reviewing what changed in markdown before committing (⇧⌘D diff)
- Reading a handbook or spec collection kept in a folder of `.md` files
- Browsing docs on a VPS over SSH, or a cloned repo, read-only

## Personas

Not applicable. This is a free single-user tool: the user, champion, and buyer
are the same person, and there is no purchase decision.

## Problems & Pain Points

**Core challenge:** Markdown on a Mac is read in tools that are wrong for
reading it. Editors put you in an editing surface you did not want. Browser
previews lose the file tree and the native feel. Quick Look shows raw-ish text
and no diagrams. GitHub's web view requires the file to be pushed.

**Why current solutions fall short:**
- **Editors** (Obsidian, Typora, VS Code) optimise for authoring; reading is a
  mode inside a writing tool.
- **Browser previews** are a tab, not an app — no sidebar, no outline, no native
  chrome, and often no Mermaid or math without a plugin.
- **Quick Look** cannot render diagrams, math, or a multi-file tree.

**What it costs:** Constant context-switching, and diagrams and equations that
simply do not render until the file is pushed somewhere that renders them.
**[assumed]**

**Emotional tension:** Mild but persistent friction — the sense that a Mac app
ought to exist for this and doesn't. **[assumed — no user research]**

## Competitive Landscape

**Direct** (same solution, same problem):
- **Marked 2** — the established macOS markdown previewer. Paid, mature, deep
  export and preview-processor support. Not open source; not Liquid Glass-era
  native.
- **Quick Look markdown plugins** — free and instant, but no tree, no outline,
  no diagrams.

**Secondary** (different solution, same problem):
- **Obsidian / Typora / iA Writer** — editors whose preview mode people use for
  reading.
- **VS Code markdown preview** — already open, but a pane inside an IDE.

**Indirect** (conflicting approach):
- **Push to GitHub and read it in the browser** — free and familiar, but
  requires committing and a round trip.

**How they fall short:** none combine a native Mac shell, bundled offline
Mermaid/LaTeX rendering, a multi-root file tree, and git awareness. **[assumed]**

## Differentiation

**Key differentiators:**
- **Genuinely native shell** — SwiftUI/AppKit toolbar, sidebar, outline, find;
  Liquid Glass on macOS 26 with an `NSVisualEffectView` fallback on 13–15.
- **Rendering with no network** — Mermaid, KaTeX, and highlight.js are bundled.
  The only network access in the app is Sparkle's update check.
- **Remote and cloned folders** — add a folder over SSH (`rsync`, read-only) or
  by git clone URL, reusing existing SSH and git credentials and **storing
  none**.
- **Git-aware** — sidebar status badges, side-by-side diff (⇧⌘D) against
  unstaged, staged, the last commit, or any branch.
- **A reader on purpose** — it does not try to be an editor. ⇧⌘E hands the file
  to the editor you already chose, and the watcher turns that into a live
  preview.
- **CLI companion** — `reader file.md`, `reader .`, `reader remote user@host:/path`.

**Why that's better:** reading markdown stops being a compromise inside a tool
built for something else.

## Objections

**[assumed — no sales conversations exist; these are the predictable ones]**

1. *"Why not just use my editor's preview?"* — Because it is a pane in a writing
   tool, without a file tree across folders, an outline, or offline diagrams.
2. *"Apple silicon only, and it isn't notarized?"* — The build is arm64 and
   ad-hoc signed, so the first launch needs right-click → Open. Documented in
   the install guide.
3. *"Another markdown app?"* — It is a viewer, not another editor, and it is
   free and MIT.

**Anti-personas — who this is NOT for:**
- People who want to **write** markdown (it deliberately does not edit)
- Intel Mac, Windows, or Linux users
- People looking for a note-taking or PKM system with backlinks and a graph
- Teams wanting sync, collaboration, or sharing

## Switching Dynamics

- **Push:** Editor previews feel wrong for reading; diagrams don't render until
  pushed; Quick Look is too thin.
- **Pull:** It looks and behaves like a Mac app; diagrams and math just work
  offline; remote folders need no sync setup.
- **Habit:** The editor is already open, and its preview is already there.
- **Anxiety:** "Is a free single-developer app maintained?" and the unnotarized
  first-launch warning. **[assumed]**

## Customer Language

**Words to use:** viewer, reader, preview, render, live preview, file tree,
outline, folder, repository, diff, offline, native.

**Words to avoid:** *powerful*, *seamless*, *beautiful*, *effortless*, *modern*,
*revolutionary*, *game-changing* — and any benefit-led marketing adjective.
Feature docs say what a thing does before why it is nice. See
`.claude/skills/reader-docs/references/voice.md`.

**Product glossary — use these exactly:**

| Term | Means |
|---|---|
| **Root** | A folder added to the sidebar. There can be many |
| **Remote folder** | A folder `rsync`'d read-only from a host over SSH |
| **Cloned folder** | A git repository cloned read-only by URL |
| **Canvas** | The area a document is laid out in (Narrow / Wide / Full Width) |
| **Outline** | The heading structure of the open document (⇧⌘B) |
| **Scope** | What a diff compares against: Unstaged, Staged, All, or a branch |
| **Quick Open** | The ⌘P fuzzy switcher across every root |

**How users describe the problem / solution:** **[unknown]** — no support
threads, reviews, or interviews exist to quote verbatim. Fill this in from real
user words when there are any; do not paraphrase marketing copy into this slot.

## Brand Voice

**Tone:** Direct, technical, unhedged. Confident about what the app does and
plain about what it does not.

**Style:** Second person ("you add a folder"). Short sentences, one idea each.
UI elements named exactly as they render. Shortcuts parenthesised after the
label — "Toggle outline (⇧⌘B)".

**Personality:** precise, understated, native-feeling, opinionated, honest.

**Note on register:** the marketing site is allowed a little more flourish than
the docs — the landing page says "feels truly native" and uses a gradient — but
documentation stays plain. When they conflict, the docs' voice rules win.

## Proof Points

**[unknown]** — there are no testimonials, user counts, install numbers, star
counts, or named users recorded in this repository. Do not cite any until real
ones exist.

What can be stated factually today:
- Free and MIT licensed
- Ships with no telemetry; the only network call is Sparkle's update check
- Renders Mermaid, LaTeX, and syntax highlighting entirely offline
- Auto-updates in place via Sparkle

## Goals

**Primary goal:** People who read markdown on a Mac install it and keep using
it. **[assumed]**

**Key conversion action:** Download on Mac — the DMG from the latest release, or
`brew install --cask reader-md`.

**Secondary:** GitHub stars and contributors.

**Current metrics:** **[unknown]**

## Changelog

### 1.0.0 — 2026-08-12
- Initial draft, auto-generated from the repository (README, site copy,
  `docs/features.md`, `CLAUDE.md`, and the app source) for the `reader-docs`
  skill to use as shared context when writing feature pages.
- Assumptions and gaps are marked inline rather than filled with invented
  detail: there is no user research, no sales history, and no published metrics
  in this repo.
