---
title: Agent skill
category: Reference
order: 22
summary: Teach Claude Code, Codex, or Cursor to open the plan, spec, or report it just wrote in Reader.md.
related: [cli, install, faq]
---

# Agent skill

Reader.md ships an [agent skill](../skills/reader-md/SKILL.md) that teaches a
coding agent to run `reader` on the plan, spec, design doc, report, or review it
just wrote, so the document opens in a reading window as the agent finishes
rather than scrolling past in the terminal. Live reload then shows every later
edit the agent makes, with your scroll position kept.

## Before you install

The skill drives the `reader` command, so that has to be on your PATH. Homebrew
puts it there; with the DMG, use **File → Install `reader` Command Line Tool…**
once. See [Install](install.md).

Without `reader`, the skill does nothing: an agent opening a document on its
own skips it quietly, and one you asked to open a file tells you how to install
the command.

## Install

For Claude Code, Codex, Cursor, and the other agents the
[`skills`](https://github.com/vercel-labs/skills) installer knows:

```bash
npx skills add jnahian/reader.md --skill reader-md -g
```

`-g` installs it for every project; without it the skill lands in the directory
you ran the command from, and only agents working there will see it.

Or copy the one file into place by hand — for Claude Code:

```bash
mkdir -p ~/.claude/skills/reader-md
curl -fsSL https://raw.githubusercontent.com/jnahian/reader.md/main/skills/reader-md/SKILL.md \
  -o ~/.claude/skills/reader-md/SKILL.md
```

An agent that reads `AGENTS.md` rather than skills needs only a line there:

```markdown
After writing a markdown document for me to read (a plan, spec, design doc,
report, or review), open it with `reader <absolute path>` if the `reader`
command exists.
```

## When it opens a file

- **On its own**, after the agent writes or substantially rewrites a markdown
  document meant for you: a plan, spec, design doc, report, or review.
- **When you ask** it to open, show, or preview a markdown file in Reader.md.

It stays out of the way for a small edit to an existing doc, for a README or
changelog touched as part of a code change, and for markdown written for a
machine or another agent: memory files, `CLAUDE.md`, `AGENTS.md`, prompts,
skills. Asking the agent to *read* a file is not asking it to open one.

## What it does

- **Opens a file once.** Reader.md re-renders on every save, so the agent does
  not re-run `reader` after each edit, only when it moves on to a different
  document.
- **One file per command.** If the agent wrote several, it opens the one to read
  first and names the others in its reply.
- **Pipes text that lives elsewhere**, such as a PR body:
  `gh pr view 12 --json body -q .body | reader -`. Anything it writes itself
  goes in a file, because a piped document is a temporary copy deleted a day
  later.
- **Diff mode only when you ask for a diff.** `reader <file> --diff` stays on
  for every document opened afterwards; ⇧⌘D turns it off.
- **Leaves your sidebar alone.** It never runs `reader <folder>`, `reader rm`,
  or `reader remote` unless you ask.

## Updating and removing

Installed copies do not update themselves. To pick up a newer version of the
skill, run the install command again.

To remove it:

```bash
npx skills remove reader-md -g
```

Or delete the folder you copied it into, such as `~/.claude/skills/reader-md`.

A walkthrough of the agent workflow is in
[Review what your coding agent writes](use-cases/review-ai-agent-docs.md).
