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
graph TD
  Shell[Native shell] --> State[Shared state]
  State --> Content[Content pane]
  State --> Sidebar[File tree]
  Content --> Render[Renderer]
  Render --> Diagrams[Diagrams]
  Render --> Math[Math]
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

# --- git fixture -------------------------------------------------------------
# A repository cannot be nested inside this one, so it is built here. Dates are
# pinned; without that, every sweep produces new commit SHAs and new diffs.
REPO="$ROOT/field-guide"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" config user.name "Field Guide"
git -C "$REPO" config user.email "guide@example.com"
git -C "$REPO" config commit.gpgsign false

export GIT_AUTHOR_DATE="2026-01-15T09:00:00+00:00"
export GIT_COMMITTER_DATE="2026-01-15T09:00:00+00:00"

cat > "$REPO/README.md" <<'EOF'
# Field Guide

Notes that travel with the project.

## Scope

One page per decision. If it needs two, it was two decisions.
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

# Dirty state, so the sidebar badges and the diff view have something to show.
# Modified (M):
cat >> "$REPO/README.md" <<'EOF'

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
