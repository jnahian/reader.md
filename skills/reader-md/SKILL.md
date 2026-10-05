---
name: reader-md
description: Open a markdown file in Reader.md, the macOS markdown reader, so the user can read it in a real window instead of the terminal or an editor tab. Use right after writing or substantially rewriting a markdown document the user is meant to read — a plan, spec, design doc, report, or review — and whenever the user asks to open, show, or preview a markdown file in Reader.md.
---

# Open markdown in Reader.md

When you finish a markdown document the user is going to read, open it for them
with the `reader` command, passing the file's **absolute path** — `reader`
resolves a relative one against the shell's working directory, which is not
always where you wrote the file:

```bash
if command -v reader >/dev/null; then reader /abs/path/to/plan.md; fi
```

The app launches if it is not running, and the file does not have to be in a
folder the user has added.

## When

- **On your own:** you wrote or substantially rewrote a `.md`, `.markdown`,
  `.mdown`, `.mdx`, `.mkd`, `.mkdn`, or `.mdwn` file whose audience is the user — a plan, spec, design
  doc, report, or review.
- **When asked:** the user asks to open, show, or preview a markdown file in
  Reader.md.

Not on your own for a small edit to an existing doc, for repo housekeeping done
as part of a code change (README, changelog), or for markdown written for a
machine or another agent (memory files, `CLAUDE.md`, `AGENTS.md`, prompts,
skills). And being asked to *read* a file means you read it — that is not a
request to open it.

## If `reader` is not installed

The `if` guard above makes a missing command a quiet no-op. Reader.md is macOS
only, and when you were opening a document on your own that is the right
outcome: say nothing and carry on.

When the user *asked* for Reader.md, tell them instead: the command comes with
the Homebrew cask, and a DMG install adds it from **File → Install `reader`
Command Line Tool…**.

## How

- **Do not re-run it after each edit.** Reader.md live-reloads the open file on
  every save with the scroll position kept. Run `reader` again only when you
  have opened a different document since, because the window shows one at a
  time.
- **One file per command.** If you wrote several, open the one to read first
  and name the others in your reply.
- **Text that already lives somewhere else** — a PR body, command output — can
  be piped: `gh pr view 12 --json body -q .body | reader -`. A piped document is
  a temporary copy that is deleted a day later, so anything you author yourself
  goes in a file.
- **Diff mode only when the user asks for a diff:** `reader /abs/path/spec.md --diff`
  shows the file's uncommitted changes side by side, so it is empty for a file
  you have already committed. It also stays on for every document opened
  afterwards, and `reader` cannot turn it off — tell the user ⇧⌘D does.
- Afterwards, tell the user in one line that the file is open in Reader.md.

`reader` exits 1 with the reason on stderr — a path that does not exist, a file
that is not markdown, an app that could not be launched. Correct a wrong path
once; otherwise report the reason and move on.

Do not run `reader <folder>`, `reader .`, `reader rm`, or `reader remote` on your
own. Those change the user's sidebar, so they are for when the user asks.
