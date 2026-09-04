#!/bin/bash
# Generates the screenshot fixture corpus into a temp directory and prints its
# path. Never commit fixtures: FileScanner scans roots recursively for markdown,
# so committed fixtures would show up in the sidebar beside the real docs — and
# inside the screenshots.
#
# Everything here is deterministic. Commit dates are pinned so that diff and
# badge screenshots don't churn on every sweep.
set -euo pipefail

# Deliberately NOT $TMPDIR. Quick Open renders a file's full folder chain, so a
# fixture under $TMPDIR puts /var/folders/9h/xb4dkknn74z968nc1dmynjp00000gn/T
# — a per-machine identifier — into a published screenshot. A short fixed path
# keeps the breadcrumb clean and makes it identical on every machine, which is
# what --verify-repro compares.
ROOT="/tmp/reader-md-docs"
rm -rf "$ROOT"
mkdir -p "$ROOT/field-notes/guides" "$ROOT/field-notes/reference"

cat > "$ROOT/field-notes/index.md" <<'EOF'
---
title: Field Notes
updated: 2026-03-04
tags: [handbook, reference]
---

# Field Notes

A small working handbook. Start with the [setup guide](guides/setup.md), then
skim the [reference](reference/shortcuts.md).

## What lives here

| Section | Contents |
|---|---|
| Guides | Task-shaped walkthroughs |
| Reference | Tables and lookups |

> Notes are written as they are learned, and corrected as they are disproven.
EOF

cat > "$ROOT/field-notes/guides/setup.md" <<'EOF'
# Setting up a workspace

A long enough document to scroll, with enough headings to fill an outline.

## Before you start

You will need a terminal, a text editor, and about twenty minutes.

## Installing the toolchain

Install the compiler first. Everything else depends on it.

```bash
brew install swiftlint
swift build -c release
```

### Verifying the install

Run the version command and confirm the output.

### Common problems

If the command is not found, your shell profile is not being sourced.

## Configuring the editor

Point the editor at the workspace root, not at an individual file.

### Themes

Pick a light theme for daylight work.

### Extensions

Fewer is better. Each one costs startup time.

## First build

The first build is slow because nothing is cached yet.

## Next steps

Read the reference, then come back and skim this again.
EOF

cat > "$ROOT/field-notes/guides/architecture.md" <<'EOF'
# Architecture

The shape of the system, and why it is shaped that way.

```mermaid
graph LR
  Shell[Native shell] --> State[Shared state]
  State --> Sidebar[File tree]
  State --> Content[Content pane]
  Content --> Render[Renderer]
```

## Throughput

Given a queue of $n$ documents and a service rate $\mu$, the steady-state wait is:

$$W = \frac{1}{\mu - \lambda}$$

which is why $\lambda$ must stay below $\mu$.

## Layers

The shell owns layout. The renderer owns content. Nothing crosses that line.
EOF

cat > "$ROOT/field-notes/reference/shortcuts.md" <<'EOF'
# Reference

## Codes

| Code | Meaning |
|---|---|
| `A` | Added |
| `M` | Modified |
| `U` | Unmerged |

## Example

```swift
struct Document: Identifiable {
    let id: UUID
    let title: String
    var wordCount: Int
}
```
EOF

cat > "$ROOT/field-notes/reference/glossary.md" <<'EOF'
# Glossary

**Canvas** — the area a document is laid out in.

**Outline** — the heading structure of the current document.

**Root** — a folder added to the sidebar.
EOF

# --- agent-run fixture -------------------------------------------------------
# A second root, deliberately separate from field-notes. Every other manifest
# seeds only <fixtures>/field-notes, so nothing added here can change the
# sidebar in the committed screenshot sets. Used by docs/hero.shots.json for
# the README and landing-page hero image.
mkdir -p "$ROOT/agent-run/runs"

cat > "$ROOT/agent-run/plan.md" <<'EOF'
# Extract the settings sheet

*Generated 2026-03-04 · 6 phases · 34 tasks · unreviewed*

The settings sheet reaches into three view models directly. This plan moves it
behind a single store, in phases that each leave the app building.

```mermaid
graph LR
  Sheet[SettingsSheet] --> Store[SettingsStore]
  Store --> Disk[(UserDefaults)]
  Store --> Views[Observers]
```

## Phase 1 — Read the current shape

- [x] Map every caller of `SettingsStore`
- [x] List the defaults keys written outside it
- [ ] Note which writes race the in-memory copy
- [ ] Decide what stays a direct read

## Phase 2 — Introduce the store

One owner for every preference, with the sheet reading through it.

### The interface

`SettingsStore` exposes typed properties, not a dictionary. A missing key
returns the declared default rather than nil.

### Migrating the keys

Keys move one at a time. Each move is its own commit, so a bad default can be
reverted without unwinding the phase.

## Phase 3 — Move the writes

Every write goes through the store. Direct defaults calls are removed as their
key migrates.

### Ordering

Writes are ordered so the sheet never observes a half-migrated state.

## Phase 4 — Delete the old path

The three view models drop their preference properties once nothing reads them.

## Phase 5 — Tests

Round-trip every key, then assert the declared defaults survive a cold start.

## Phase 6 — Ship

Behind no flag. The change is invisible if it works.
EOF

cat > "$ROOT/agent-run/spec.md" <<'EOF'
# Spec — one owner for preferences

Preferences are read in three places and written in five. This is the design
for collapsing that to one store.

## Constraints

The on-disk format does not change. A downgrade must still read its own keys.
EOF

cat > "$ROOT/agent-run/review.md" <<'EOF'
# Review

Notes from reading the plan back.

- Phase 3 assumes Phase 2 landed whole. Say so.
- The cold-start test belongs in Phase 2, not Phase 5.
EOF

cat > "$ROOT/agent-run/runs/2026-03-04.md" <<'EOF'
# Run 2026-03-04

Phases 1 and 2 complete. Phase 3 stopped on the ordering question.
EOF

# --- git fixture -------------------------------------------------------------
# A repository cannot be nested inside this one, so it is built here. Dates are
# pinned; without that, every sweep produces new commit SHAs and new diffs.
REPO="$ROOT/field-guide"
mkdir -p "$REPO"
# -b main: without it the branch name comes from the machine's
# init.defaultBranch, and the diff-scope popover lists whatever that happened
# to be — main on one machine, master on the next.
git init -q -b main "$REPO"
git -C "$REPO" config user.name "Field Guide"
git -C "$REPO" config user.email "guide@example.com"
git -C "$REPO" config commit.gpgsign false

export GIT_AUTHOR_DATE="2026-01-15T09:00:00+00:00"
export GIT_COMMITTER_DATE="2026-01-15T09:00:00+00:00"

# Long enough that the working-copy edits below land in two separate hunks —
# a short file collapses them into one, and the diff outline lists a single row.
cat > "$REPO/README.md" <<'EOF'
# Field Guide

Notes that travel with the project.

## Scope

One page per decision. If it needs two, it was two decisions.

## Format

Every page opens with the decision itself, then the reasoning, then whatever we
ruled out along the way.

## Review

A page is revisited when something it assumed stops being true.
EOF

cat > "$REPO/decisions.md" <<'EOF'
# Decisions

## Storage

We keep documents on disk and read them directly.

## Rendering

Rendering happens in one place so that it behaves the same everywhere.

## Navigation

The sidebar is a tree. Recents sit above it.
EOF

git -C "$REPO" add -A
git -C "$REPO" commit -qm "Add the field guide"

export GIT_AUTHOR_DATE="2026-02-02T14:30:00+00:00"
export GIT_COMMITTER_DATE="2026-02-02T14:30:00+00:00"

cat >> "$REPO/decisions.md" <<'EOF'

## Search

Filtering the tree and searching a document are different tasks, so they get
different controls.
EOF

git -C "$REPO" add -A
git -C "$REPO" commit -qm "Record the search decision"

# Two more refs, so the diff-scope popover has a Branches section to show — the
# checked-out branch is dropped from that list, so `main` alone leaves it empty.
# Cut at the earlier commit, so comparing against either is a real diff.
git -C "$REPO" branch release HEAD~1
git -C "$REPO" branch drafts HEAD~1

# Dirty state, so the sidebar badges and the diff view have something to show.
# Modified (M). The working copy rewrites a sentence as well as appending a
# section: an append-only change diffs as whole added lines, and the word-level
# highlighting has nothing to highlight.
cat > "$REPO/README.md" <<'EOF'
# Field Guide

Short notes that travel with the code.

## Scope

One page per decision. If it needs two, it was two decisions.

## Format

Every page opens with the decision itself, then the reasoning, then whatever we
ruled out along the way.

## Review

A page is revisited when something it assumed stops being true.

## Conventions

Headings are sentence case. Links are relative.
EOF

# Staged add (A):
cat > "$REPO/roadmap.md" <<'EOF'
# Roadmap

Near-term work, in the order we expect to do it.

1. Finish the reference pages
2. Revisit the glossary
EOF
git -C "$REPO" add roadmap.md

# Untracked (?):
cat > "$REPO/scratch.md" <<'EOF'
# Scratch

Half-formed notes that are not ready to be filed.
EOF

echo "$ROOT"
