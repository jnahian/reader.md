# Manual Shots

States the harness cannot reach with keystrokes and the `reader` CLI. Mark them
`"manual": true` in the manifest; `capture.sh` skips them and warns if the file
is missing.

Shoot them against the **same** fixture corpus and window geometry as the
scripted shots, so they sit consistently beside them:

```bash
root=$(.claude/skills/reader-docs/scripts/fixtures.sh)
BUNDLE_ID=com.nahian.reader-md.shots APP_OUT=build/shots ./make-app.sh
defaults write com.nahian.reader-md.shots reader.md.folders -array "$root/field-notes" "$root/field-guide"
defaults write com.nahian.reader-md.shots reader.md.theme -string dark
defaults write com.nahian.reader-md.shots lastSeenBuild -string 999999999999
killall cfprefsd
open -a build/shots/Reader.md.app
```

That `lastSeenBuild` line is not optional — without it the app opens its What's
New changelog over the content pane and you photograph that instead.

Set the window to 1400×900 at (120, 80), hide your other apps (⌥⌘H — Liquid
Glass samples what is behind the window), then capture with ⇧⌘4 followed by
Space to get the window. Scale the result to 2400px wide so it matches the
scripted shots:

```bash
ffmpeg -v error -y -i in.png -vf scale=2400:-1 -compression_level 100 \
  docs/assets/screenshots/<page>/<id>.png
```

## The list

| Shot | Page | State to reach |
|---|---|---|
| Context menu on a file | navigating | Right-click a file in the tree |
| Context menu on a root | library | Right-click a root header |
| Drag and drop | library | Mid-drag of a markdown file over the content pane |
| Add Remote sheet | library | Sidebar footer → **Add Remote** |
| Always Open With | exporting | Right-click a file → **Always Open With** |

Check each for leaked personal data before it ships — a Finder-adjacent shot is
the easiest place for a real path to appear, and the Add Remote sheet will show
whatever host you type, so use a placeholder like `user@example.com:/srv/notes`.

One more trap: a manual shot leaves your pointer somewhere in the window, and a
tooltip may be up when you press the shutter. Move the pointer well away and
wait a beat before capturing.
