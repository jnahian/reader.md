# Command line

```
reader <file.md>                   open a markdown file
reader <file.md> --diff            open it in diff mode (git changes)
reader <folder>                    add a folder to the sidebar
reader .                           add the current directory
reader remote me@vps:/srv/docs     add a remote (SSH) folder — opens a confirmation sheet
reader ls                          list configured folders
reader rm <name|path>              remove a folder
git diff | reader -                open piped markdown
```

Homebrew puts `reader` on your PATH automatically. If you installed from the DMG, use
**File → Install `reader` Command Line Tool…**, and launch the app once first so macOS clears
quarantine from the bundle.

`reader` drives the app rather than replacing it: each command hands a `readermd://` URL to
Reader.md, which does the work. `reader ls` reads the app's saved folders directly, so a folder
added a moment ago may take a beat to appear.

It behaves in scripts: a bad path, an unknown option, or a malformed command exits **1** with the
reason on stderr, so `reader remote "$HOST:$DIR" || handle_error` sees the failure. `reader` with
no arguments (or `--help`) prints usage to stdout and exits 0.
