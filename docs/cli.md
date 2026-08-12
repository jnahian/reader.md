---
title: Command line
category: Reference
order: 21
summary: The reader command — open files, add folders, list and remove them, and pipe markdown in.
related: [install, features, remote]
---

# Command line

```
reader <file.md>                   open a markdown file
reader <file.md> --diff            open it as a diff against git
reader <folder>                    add a folder to the sidebar
reader .                           add the current directory
reader remote me@vps:/srv/docs     add a remote (SSH) folder
reader ls                          list configured folders
reader rm <name|path>              remove a folder
git diff | reader -                open piped markdown
```

Homebrew puts `reader` on your PATH automatically. If you installed from the
DMG, use **File → Install `reader` Command Line Tool…**, and launch the app once
first so macOS clears quarantine from the bundle.

`reader` drives the app rather than replacing it: each command hands a
`readermd://` URL to Reader.md, which does the work — including any preference
write. Reader.md launches if it is not already running.

## Opening

A path can be relative, absolute, or start with `~`. Anything that is not a
folder has to be markdown — `.md`, `.markdown`, `.mdown`, or `.mdx` — and a path
that does not exist fails before the app is bothered.

`--diff` opens the file as a side-by-side diff, as ⇧⌘D does. It is position
independent, it needs a file rather than a folder, and diff mode is sticky, so
the next document you open is a diff too until you toggle it back.

## Folders

A folder argument adds a root; `reader .` adds the one you are standing in. See
[Finding your files](features/library.md) for what a root is.

`reader ls` prints one line per folder, name first, then where it comes from:

```
field-notes  /Users/you/Documents/field-notes
vps-docs     me@vps:/srv/docs
handbook     https://github.com/example/handbook.git
```

It reads the app's saved folders directly rather than asking the app, so a
folder added a moment ago may take a beat to appear.

`reader rm` takes either the name in that first column or the folder's path,
normalized the same way adding it was — `reader rm ~/docs/` matches a root added
as `reader ~/docs`. Removing a root leaves the folder itself alone.

## Remote folders

`reader remote` takes an SSH destination and an absolute path on that host,
separated by a colon, and opens the **Add Remote** sheet with the fields already
filled in so you can confirm or adjust them.

It is SSH only. A clone URL is not a valid argument here — add a repository from
the sheet itself (⌥⌘A, then **Git**), which is where the URL forms are
documented. See [Remote and cloned folders](features/remote.md).

## Piping

`reader -` reads a document from standard input and opens it:

```bash
git diff | reader -
pandoc notes.rst -t gfm | reader -
```

Piped documents are written to a temporary file, so they can be scrolled,
searched, and exported like any other. They cannot be favorited or handed to an
editor, and they are cleaned up a day later.

A bare `reader -` on a terminal — with nothing piped in — says so and exits
rather than waiting for you to work out that it wants ⌃D.

## In scripts

A bad path, an unknown option, or a malformed command exits **1** with the
reason on stderr, so `reader remote "$HOST:$DIR" || handle_error` sees the
failure. `reader` with no arguments, or `--help`, prints usage to stdout and
exits **0**.
