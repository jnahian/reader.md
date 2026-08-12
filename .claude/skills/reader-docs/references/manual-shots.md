# Manual Shots

States the harness cannot reach at all. Mark them `"manual": true` in the
manifest; `capture.sh` skips them and warns if the file is missing.

**Check the manifest schema before assuming a state is manual.** `click`,
`rclick` and `drag` actions exist, so a popover, a context menu, or a text
selection is scriptable now — what remains manual is a state in a *different
window* (the harness captures the document window and asserts its size), or one
that cannot be held still while a capture runs.

Shoot them against the **same** fixture corpus and window geometry as the
scripted shots, so they sit consistently beside them:

```bash
root=$(.claude/skills/reader-docs/scripts/fixtures.sh)
BUNDLE_ID=com.nahian.reader-md.shots APP_OUT=build/shots ./make-app.sh
defaults write com.nahian.reader-md.shots reader.md.folders -array "$root/field-notes" "$root/field-guide"
defaults write com.nahian.reader-md.shots reader.md.theme -string dark
defaults write com.nahian.reader-md.shots lastSeenBuild -string \
  "$(defaults read build/shots/Reader.md.app/Contents/Info CFBundleVersion)"
killall cfprefsd
open -a build/shots/Reader.md.app
```

That `lastSeenBuild` line is not optional, and it has to be the build's *own*
`CFBundleVersion`: the app opens its What's New changelog whenever the stored
value is set and differs, so any other number opens it every launch.

Set the window to 1400×900 at (120, 80), hide your other apps (⌥⌘H — Liquid
Glass samples what is behind the window), then capture with ⇧⌘4 followed by
Space to get the window. Scale the result to 2400px wide so it matches the
scripted shots:

```bash
ffmpeg -v error -y -i in.png -vf scale=2400:-1 -compression_level 100 \
  docs/assets/screenshots/<page>/<id>.png
```

A shot of a window that is *not* the 1400pt document window — the Settings
window is 420pt — keeps its own 2× size instead. Upscaling a 420pt window to
2400px blurs it, and the site lays every image out responsively, so a narrower
image simply renders narrower.

## The list

| Shot | Page | State to reach | Shot? |
|---|---|---|---|
| Settings window | settings | ⌘, — a second window, and 420pt wide | yes |
| Diff scope popover | git | ⇧⌘D, then click the scope button in the toolbar | yes |
| Export dialog | exporting | ⌘E — `runModal()`, so a separate modal window | yes |
| Context menu on a file | navigating | Right-click a file in the tree | yes |
| Context menu on a root | library | Right-click a root header | not yet |
| Drag and drop | library | Mid-drag of a markdown file over the content pane | not yet |
| Always Open With | exporting | Right-click a file → **Always Open With** submenu | not yet |

The Add Remote sheet is no longer on this list: it is a sheet on the document
window, so the harness captures it like any other state — see
`docs/features/remote.shots.json`.

Check each for leaked personal data before it ships — a Finder-adjacent shot is
the easiest place for a real path to appear, and the Add Remote sheet will show
whatever host you type, so use a placeholder like `user@example.com:/srv/notes`.

One more trap: a manual shot leaves your pointer somewhere in the window, and a
tooltip may be up when you press the shutter. Move the pointer well away and
wait a beat before capturing.

## Reproducing the four that exist

Each was driven from a script rather than by hand, so re-shooting after a UI
change is a re-run and not a rediscovery. One helper lives beside the harness:

- `scripts/winid-named.swift <owner> <title>` — the window id for an exact
  title. `winid.swift` returns the first *titled* window, which is the document
  window; a panel needs to be named. It also prints every matching window and
  its layer to stderr, which is how you find the title in the first place.

`scripts/pointer.swift click|rclick|drag` takes **screen** points when run by
hand; the manifest actions of the same name take window points and let the
harness do the conversion.

Common preamble for all four: seed the shots domain the way `capture.sh` does
(the block at the top of this file), launch, hide other apps, put the window at
(120, 80) sized 1400×900, then open the fixture with the bundled `reader`.

**Converting a measured pixel to a click.** Coordinates come off a committed
2400px-wide capture of a 1400pt window, so the factor is 2400/1400 ≈ 1.714 —
*not* 2. Screen point = window origin + pixel ÷ 1.714. Park the pointer with
`cursor.swift 99999 99999` after clicking and wait ~1.5s, or the control keeps
its hover fill and a tooltip lands in the frame.

| Shot | Recipe |
|---|---|
| `settings/01-window` | ⌘, then capture `winid-named.swift Reader.md Settings`. Seed `reader.md.editorBundleID` to `com.apple.TextEdit` first, or the External editor row reads "None". Kept at its native 840px |
| `exporting/01-export` | ⌘E then capture `winid-named.swift Reader.md Save` — layer 8, so `winid.swift` returns the document window instead. The panel opens compact (name, Tags, Where, Layout), showing no browser and no personal paths. ⎋ afterwards, or the app cannot quit. Native 740px |
| `git/04-scope` | ⇧⌘D, then `rclick`-free: a left click at screen (1212, 106) — the scope button, measured at (1872, 44) of `git/03-hunks.png`. Park the cursor, then capture the document window with `screencapture -l` as usual |
| `navigating/01-menu` | `pointer.swift rclick 228 348` — the `setup.md` row. The menu is its own window, so `screencapture -l` on the document window misses it: capture the region instead (`-R 120,80,1400,900`) and crop to `1500:1000:0:240`, which keeps the sidebar and the menu and avoids the window's rounded corners, where the region capture shows desktop |
