---
name: reader-md
description: Open a markdown file in Reader.md, the macOS markdown reader, so the user can read it in a real window instead of the terminal or an editor tab. Use right after writing or substantially rewriting a markdown document the user is meant to read — a plan, spec, design doc, report, review, README — and whenever the user asks to open, show, preview, or read a markdown file.
---

# Open markdown in Reader.md

When you finish a markdown document the user is going to read, open it for them:

```bash
reader path/to/plan.md
```

The app launches if it is not running, and the file does not have to be in a
folder the user has added.

## When

- You wrote or substantially rewrote a `.md`, `.markdown`, `.mdown`, or `.mdx`
  file whose audience is the user: a plan, spec, design doc, report, review,
  changelog, README.
- The user asks to open, show, preview, or read a markdown file.

Not for a small edit to an existing doc, and not for markdown written for a
machine or another agent (memory files, `CLAUDE.md`, `AGENTS.md`, prompts,
skills) — unless the user asks.

## How

Check once per session that the command exists, and skip the whole thing
silently if it does not — it is macOS only, and a missing reader is never worth
interrupting the task for:

```bash
command -v reader >/dev/null && reader path/to/plan.md
```

- **Open once.** Reader.md live-reloads the open file on every save with the
  scroll position kept, so keep editing the file rather than re-running `reader`.
- **One file per command.** If you wrote several, open the one to read first
  and name the others in your reply.
- **You changed a file git already tracks:** `reader path/to/spec.md --diff`
  opens it as a side-by-side diff against git. Diff mode is sticky — the next
  document opens as a diff too until the user toggles it off (⇧⌘D) — so use it
  when the change is the point, not by default.
- **Markdown that is not a file:** pipe it. `gh pr view 12 --json body -q .body | reader -`
- Afterwards, tell the user in one line that the file is open in Reader.md.

`reader` exits 1 with the reason on stderr when a path does not exist or is not
markdown. Report that; do not retry.

Do not run `reader <folder>`, `reader .`, `reader rm`, or `reader remote` on your
own. Those change the user's sidebar, so they are for when the user asks.
