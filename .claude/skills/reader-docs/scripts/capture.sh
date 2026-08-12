#!/bin/bash
# Executes a shot manifest against an isolated build of Reader.md.
#
# Design notes worth knowing before editing:
#   * screencapture -l <winid> captures the window with no cursor and no
#     shadow. In VIDEO mode -l is silently IGNORED and you get the whole
#     screen, so clips use -R with the window's own bounds instead.
#   * Keystrokes go to whatever app is frontmost. Focus can be stolen mid-run
#     (a chat notification will do it), so every keystroke is guarded.
#   * There is no selector to wait on, so "is it done rendering?" is answered
#     by capturing twice and comparing bytes.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
APP_NAME="Reader.md"
SHOTS_DOMAIN="com.nahian.reader-md.shots"
REAL_DOMAIN="com.nahian.reader-md"
# The harness drives its OWN build, never build/Reader.md.app. Sharing that
# path is how a run ends up against the real preference domain: seeding
# com.nahian.reader-md.shots does nothing if the app you launch is the default
# build, and the capture silently fills with real folders and real filenames.
APP_DIR="$REPO/build/shots"
APP="$APP_DIR/$APP_NAME.app"
READER="$APP/Contents/MacOS/reader"

MANIFEST="${1:-}"
[ -n "$MANIFEST" ] || { echo "usage: capture.sh <manifest.json> [--only <shot-id>] [--verify-repro]" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "capture: no such manifest: $MANIFEST" >&2; exit 2; }

ONLY=""
VERIFY=0
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --only)          ONLY="${2:-}"; shift 2 ;;
    --verify-repro)  VERIFY=1; shift ;;
    *) echo "capture: unknown flag '$1'" >&2; exit 2 ;;
  esac
done

# --- guards ------------------------------------------------------------------

preflight() {
  for tool in jq ffmpeg sips osascript screencapture swift; do
    command -v "$tool" >/dev/null || {
      echo "capture: missing required tool '$tool'" >&2
      [ "$tool" = "ffmpeg" ] && echo "  install it with: brew install ffmpeg" >&2
      exit 3
    }
  done
  # Screenshots come back black without Screen Recording permission, which is
  # much harder to diagnose after the fact than a message here.
  if ! screencapture -x -t png /tmp/.capture-probe.png 2>/dev/null; then
    echo "capture: screencapture failed — grant this terminal Screen Recording" >&2
    echo "  System Settings > Privacy & Security > Screen Recording" >&2
    exit 3
  fi
  rm -f /tmp/.capture-probe.png
  if ! osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' >/dev/null 2>&1; then
    echo "capture: System Events failed — grant this terminal Accessibility" >&2
    echo "  System Settings > Privacy & Security > Accessibility" >&2
    exit 3
  fi
}

require_shots_domain() {
  local domain
  domain=$(jq -r '.domain // "'"$SHOTS_DOMAIN"'"' "$MANIFEST")
  if [ "$domain" = "$REAL_DOMAIN" ]; then
    echo "capture: refusing to run against the real preference domain ($REAL_DOMAIN)." >&2
    echo "  Captures against it leak real folder names and file counts, and the" >&2
    echo "  run would overwrite your saved roots. Use $SHOTS_DOMAIN." >&2
    exit 4
  fi
  DOMAIN="$domain"
}

# Builds the isolated app if missing, then ASSERTS that the bundle actually
# carries the shots identifier. Seeding a preference domain is worthless if the
# app being launched reads a different one — the assert is the guard that
# catches it, and it is not skippable.
require_shots_app() {
  if [ ! -d "$APP" ]; then
    echo "capture: building the isolated app (first run) …"
    ( cd "$REPO" && BUNDLE_ID="$DOMAIN" APP_OUT="$APP_DIR" ./make-app.sh >/dev/null )
  fi

  local got
  got=$(defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "none")
  if [ "$got" != "$DOMAIN" ]; then
    echo "capture: rebuilding the isolated app (id was '$got', expected '$DOMAIN') …"
    ( cd "$REPO" && BUNDLE_ID="$DOMAIN" APP_OUT="$APP_DIR" ./make-app.sh >/dev/null )
    got=$(defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "none")
  fi

  if [ "$got" != "$DOMAIN" ]; then
    echo "capture: '$APP' has bundle id '$got', expected '$DOMAIN'." >&2
    echo "  Refusing to run: this app would read the real preference domain and" >&2
    echo "  the screenshots would contain real folders and filenames." >&2
    exit 4
  fi
}

# --- app control -------------------------------------------------------------

seed_prefs() {
  defaults delete "$DOMAIN" 2>/dev/null || true
  # Sensible defaults for every shot; a manifest may override any of them.
  defaults write "$DOMAIN" reader.md.theme -string dark
  defaults write "$DOMAIN" reader.md.showSidebar -bool true
  defaults write "$DOMAIN" reader.md.showTOC -bool false
  defaults write "$DOMAIN" reader.md.contentWidth -string wide
  defaults write "$DOMAIN" reader.md.fontScale -float 1.0
  # A fresh domain has no lastSeenBuild, so AppState.checkWhatsNew() opens the
  # bundled CHANGELOG over the content pane and hides the sidebar. Seed a build
  # number far in the future to suppress it. (Found the hard way: the first
  # fixture capture was a screenshot of the changelog.)
  defaults write "$DOMAIN" lastSeenBuild -string 999999999999

  # Manifest overrides. Types are inferred: arrays -> -array, booleans -> -bool,
  # numbers -> -float, everything else -> -string.
  local keys key type
  keys=$(jq -r '(.prefs // {}) | keys[]' "$MANIFEST")
  for key in $keys; do
    type=$(jq -r --arg k "$key" '.prefs[$k] | type' "$MANIFEST")
    case "$type" in
      array)
        local -a vals=()
        local v
        while IFS= read -r v; do
          vals+=("${v//<fixtures>/$FIXTURES}")
        done < <(jq -r --arg k "$key" '.prefs[$k][]' "$MANIFEST")
        defaults write "$DOMAIN" "$key" -array "${vals[@]}"
        ;;
      boolean)
        defaults write "$DOMAIN" "$key" -bool "$(jq -r --arg k "$key" '.prefs[$k]' "$MANIFEST")" ;;
      number)
        defaults write "$DOMAIN" "$key" -float "$(jq -r --arg k "$key" '.prefs[$k]' "$MANIFEST")" ;;
      *)
        defaults write "$DOMAIN" "$key" -string "$(jq -r --arg k "$key" '.prefs[$k]' "$MANIFEST" | sed "s|<fixtures>|$FIXTURES|g")" ;;
    esac
  done
  killall cfprefsd 2>/dev/null || true
}

# Waits for BOTH a CGWindowID and an Accessibility window. They do not become
# available at the same moment: CGWindowList sees the window first, and driving
# it through System Events before its AX window exists fails with "Can't get
# window 1 ... Invalid index".
launch_app() {
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  sleep 1.5
  open -a "$APP"
  # A previous run may have left it hidden; a hidden app has no on-screen
  # window and launch would time out waiting for one.
  osascript -e "tell application \"System Events\" to set visible of process \"$APP_NAME\" to true" >/dev/null 2>&1 || true
  local i ax
  for i in $(seq 1 80); do
    WINID=$(swift "$HERE/winid.swift" "$APP_NAME" 2>/dev/null | head -1) || WINID=""
    if [ -n "$WINID" ]; then
      # Count only real document windows: the app also exposes an unnamed
      # AXSystemDialog that sorts ahead of it and is NOT what we want to drive.
      ax=$(osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to count of (windows whose value of attribute \"AXSubrole\" is \"AXStandardWindow\")" 2>/dev/null || echo 0)
      [ "${ax:-0}" -ge 1 ] && { assert_running_is_shots_app; return 0; }
    fi
    sleep 0.25
  done
  echo "capture: app window never appeared" >&2
  exit 5
}

# Both builds are called "Reader.md", so `tell application "Reader.md"` is
# ambiguous if the normal build is also running — and would happily drive the
# real one. Require exactly one, and require it to be ours.
assert_running_is_shots_app() {
  local n id
  n=$(osascript -e "tell application \"System Events\" to count of (processes whose name is \"$APP_NAME\")" 2>/dev/null || echo 0)
  if [ "${n:-0}" -ne 1 ]; then
    echo "capture: $n processes named '$APP_NAME' are running." >&2
    echo "  Quit your normal Reader.md before capturing — otherwise AppleScript" >&2
    echo "  cannot tell the two apart and may drive the wrong one." >&2
    exit 4
  fi
  id=$(osascript -e "tell application \"System Events\" to get bundle identifier of first process whose name is \"$APP_NAME\"" 2>/dev/null || echo none)
  if [ "$id" != "$DOMAIN" ]; then
    echo "capture: the running '$APP_NAME' is '$id', not '$DOMAIN'." >&2
    echo "  Refusing to drive the real app." >&2
    exit 4
  fi
}

# Guarantees the app is frontmost before a keystroke is sent. It re-activates
# first — the terminal reclaims focus routinely and that is not an error — and
# only fails if activation will not stick, which means something is actively
# fighting for focus and keystrokes would land in it.
assert_frontmost() {
  local front attempt
  for attempt in 1 2 3; do
    front=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')
    [ "$front" = "$APP_NAME" ] && return 0
    osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 || true
    sleep 0.4
  done
  front=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')
  [ "$front" = "$APP_NAME" ] && return 0
  echo "capture: $APP_NAME will not stay frontmost — '$front' keeps taking focus." >&2
  echo "  Aborting rather than sending keystrokes to another application." >&2
  echo "  Close or quiet that app and re-run." >&2
  exit 6
}

# The window restores its autosaved frame shortly after launch, which can land
# AFTER a resize and silently undo it — producing differently-sized shots. So
# set, verify, and retry rather than setting once and hoping.
set_geometry() {
  local w="$1" h="$2" attempt got
  for attempt in 1 2 3 4 5; do
    # Tolerate transient AX errors ("Invalid index" while the window is being
    # created or replaced) — that is exactly what the retry loop is for.
    osascript >/dev/null 2>&1 <<EOF || true
tell application "$APP_NAME" to activate
delay 0.3
tell application "System Events" to tell process "$APP_NAME"
  set win to first window whose value of attribute "AXSubrole" is "AXStandardWindow"
  set size of win to {$w, $h}
  set position of win to {120, 80}
end tell
EOF
    sleep 0.6
    got=$(osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to get size of (first window whose value of attribute \"AXSubrole\" is \"AXStandardWindow\")" 2>/dev/null | tr -d ' ' || echo "none")
    if [ "$got" = "$w,$h" ]; then
      # The window id changes if the window was recreated; re-resolve it or
      # screencapture fails with "could not create image from window".
      WINID=$(swift "$HERE/winid.swift" "$APP_NAME" | head -1)
      return 0
    fi
  done
  echo "capture: window would not hold ${w}x${h} (got $got)" >&2
  exit 8
}

window_bounds() {
  osascript <<EOF
tell application "System Events" to tell process "$APP_NAME"
  set win to first window whose value of attribute "AXSubrole" is "AXStandardWindow"
  set p to position of win
  set s to size of win
  return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
end tell
EOF
}

# --- main --------------------------------------------------------------------

preflight
require_shots_domain
require_shots_app

FIXTURES=$("$HERE/fixtures.sh")
PAGE=$(jq -r '.page' "$MANIFEST")
WIN_W=$(jq -r '.window.width  // 1400' "$MANIFEST")
WIN_H=$(jq -r '.window.height // 900'  "$MANIFEST")

FINAL_OUT="$REPO/docs/assets/screenshots/$PAGE"
# --verify-repro captures a fresh set into a temp dir and compares it against
# the committed one, rather than overwriting what it is meant to be checking.
if [ "$VERIFY" -eq 1 ]; then
  OUT=$(mktemp -d)
else
  OUT="$FINAL_OUT"
fi
mkdir -p "$OUT" "$FINAL_OUT"

# Liquid Glass samples whatever sits behind the window, so a terminal or chat
# window behind it bleeds into the sidebar and makes two runs of the same
# manifest differ. Hiding everything else leaves only the desktop wallpaper
# back there, which is constant. Without this, cross-run SSIM lands around
# 0.95–0.99 purely from backdrop bleed.
hide_others() {
  osascript >/dev/null 2>&1 <<EOF || true
tell application "$APP_NAME" to activate
tell application "System Events"
  set visible of (every process whose visible is true and name is not "$APP_NAME") to false
end tell
EOF
  sleep 0.8
  HID_OTHERS=1
}

# Hiding the user's applications is a side effect of capturing, not something
# they asked for — always give the desktop back, including on failure.
HID_OTHERS=0
restore_others() {
  [ "$HID_OTHERS" -eq 1 ] || return 0
  osascript -e 'tell application "System Events" to set visible of every process to true' >/dev/null 2>&1 || true
}
# One EXIT trap only — a second `trap ... EXIT` silently replaces the first,
# which would have left the user's apps hidden.
RAW_DIR=""
cleanup() {
  [ -n "$RAW_DIR" ] && rm -rf "$RAW_DIR"
  restore_others
}
trap cleanup EXIT

# Every shot starts from the manifest's declared state, not from wherever the
# previous shot left the app. Without this, state leaks forward: opening the
# outline for one shot leaves it open in the next, and a find bar full of
# search matches turns the following typography shot into another find shot.
#
# It also makes --only correct. Re-shooting one shot against a leaked state
# would produce an image that does not match the committed one, and
# --verify-repro would then fail on a shot nobody had changed.
reset_state() {
  seed_prefs
  launch_app
  hide_others
  # Stills need the pointer out of the way just as much as clips do: a tooltip
  # left up by a stale hover shows in every shot taken afterwards.
  swift "$HERE/cursor.swift" 99999 99999
  set_geometry "$WIN_W" "$WIN_H"
  assert_frontmost
}

reset_state

echo "capture: $PAGE — window ${WIN_W}x${WIN_H}, fixtures at $FIXTURES"

# --- settling ----------------------------------------------------------------
# There is no selector to wait on, so "has it finished rendering?" is answered
# empirically: capture, wait, capture again, compare. Verified stable — five
# consecutive captures of a static window are byte-identical, and a
# Mermaid/KaTeX document needs two polls before it stops changing.
#
# The mandatory first delay matters: without it a state that has not STARTED
# changing yet reads as already settled.
settle() {
  local win="$1" out="$2" tries=0
  sleep 0.4
  screencapture -l "$win" -o -x "$out.a"
  while [ "$tries" -lt 40 ]; do
    sleep 0.15
    screencapture -l "$win" -o -x "$out.b"
    if cmp -s "$out.a" "$out.b"; then
      mv "$out.b" "$out"; rm -f "$out.a"
      return 0
    fi
    mv "$out.b" "$out.a"
    tries=$((tries + 1))
  done
  rm -f "$out.a" "$out.b"
  echo "capture: '$out' never settled after $tries polls" >&2
  exit 7
}

# --- video -------------------------------------------------------------------
# Clips exist only for features that ARE a motion. Note two things that differ
# from stills:
#   * screencapture -l is IGNORED in video mode (it records the whole screen),
#     so the window's own bounds are passed to -R instead.
#   * There is no settle loop — change is the content — so the timing in the
#     manifest's waitMs actions IS the choreography, and every clip is watched
#     by a human before it ships.
record_video() {
  local shot="$1" id="$2" secs x y w h rec
  secs=$(echo "$shot" | jq -r '.video.seconds // 6')
  read -r x y w h <<<"$(window_bounds)"

  # The cursor is always recorded and cannot be hidden, so park it far off the
  # window — bottom-right of the screen. (10,10) was not enough: a toolbar
  # tooltip was still up and photobombed the clip.
  swift "$HERE/cursor.swift" 99999 99999
  sleep 0.6

  KEYLOG="$RAW_DIR/$id.keys"
  : > "$KEYLOG"

  screencapture -v -V "$secs" -R "$x,$y,$w,$h" "$RAW_DIR/$id.mov" &
  rec=$!
  sleep 1
  run_actions "$shot"
  wait "$rec"
  local rec_end
  rec_end=$(python3 -c 'import time; print(time.time())')
  KEYLOG_DONE="$KEYLOG"
  KEYLOG=""

  # screencapture does not begin recording the instant it is launched, and it
  # can stop short of -V. So do not time badges from when we started it: derive
  # the recording window backwards from its ACTUAL duration. The clip covers
  # [rec_end - duration, rec_end], which is self-correcting whatever the lag.
  local dur rec_start
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RAW_DIR/$id.mov")
  rec_start=$(awk -v e="$rec_end" -v d="$dur" 'BEGIN{ printf "%.3f", e - d }')

  # Build a keystroke-badge overlay per logged key. Without this a viewer sees
  # the effect of a shortcut with nothing showing the cause, which for a
  # keyboard-driven app is most of the point.
  local inputs="" chain="[0:v]fps=30,scale=1600:-2[base]" prev="base" idx=0 ts label rel bfile
  if [ -s "$KEYLOG_DONE" ]; then
    while IFS=$'\t' read -r ts label; do
      [ -n "$label" ] || continue
      rel=$(awk -v a="$ts" -v b="$rec_start" 'BEGIN{ d=a-b; if (d<0) d=0; printf "%.2f", d }')
      idx=$((idx + 1))
      bfile="$RAW_DIR/$id.badge$idx.png"
      swift "$HERE/badge.swift" "$label" "$bfile" 42
      inputs="$inputs -i $bfile"
      chain="$chain;[$prev][${idx}:v]overlay=(W-w)/2:H-h-64:enable='between(t,$rel,$rel+1.40)'[v$idx]"
      prev="v$idx"
    done < "$KEYLOG_DONE"
  fi

  # shellcheck disable=SC2086
  ffmpeg -v error -y -i "$RAW_DIR/$id.mov" $inputs \
         -filter_complex "$chain" -map "[$prev]" \
         -c:v libx264 -crf 26 -preset slow \
         -movflags +faststart -pix_fmt yuv420p -an "$OUT/$id.mp4"
  ffmpeg -v error -y -i "$OUT/$id.mp4" -frames:v 1 -q:v 3 "$OUT/$id.poster.jpg"
  echo "  $id (video, ${secs}s, $idx keystroke badge(s))"
}

# Renders a shortcut the way the app's own docs write it: ⌃⌥⇧⌘ in Apple's
# canonical modifier order, then the key.
key_glyphs() {
  local key="$1" mods="$2" out=""
  case "$mods" in *control*) out="${out}⌃" ;; esac
  case "$mods" in *option*)  out="${out}⌥" ;; esac
  case "$mods" in *shift*)   out="${out}⇧" ;; esac
  case "$mods" in *command*) out="${out}⌘" ;; esac
  local label
  case "$key" in
    " ")  label="Space" ;;
    *)    label=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]') ;;
  esac
  printf '%s%s' "$out" "$label"
}

# Set while a clip is recording; each keystroke appends "<epoch>\t<glyphs>" so
# the badge overlay lands on the exact frame the key was pressed rather than on
# a guess derived from the manifest's waitMs values.
KEYLOG=""

run_actions() {
  local shot="$1" n i
  n=$(echo "$shot" | jq '(.actions // []) | length')
  [ "$n" -eq 0 ] && return 0
  for i in $(seq 0 $((n - 1))); do
    local action key mods ms cli
    action=$(echo "$shot" | jq -c ".actions[$i]")
    key=$(echo "$action" | jq -r '.key // empty')
    ms=$(echo "$action" | jq -r '.waitMs // empty')
    cli=$(echo "$action" | jq -r '.reader // empty')
    if [ -n "$key" ]; then
      assert_frontmost
      mods=$(echo "$action" | jq -r '(.mods // []) | map(. + " down") | join(", ")')
      # AppleScript string literals need \ and " escaped. Without this, the
      # canvas-width shortcut (⇧⌘\) produces `keystroke "\"` and osascript
      # dies with 'Expected " but found end of script'.
      local esc="$key"
      esc="${esc//\\/\\\\}"
      esc="${esc//\"/\\\"}"
      if [ -n "$mods" ]; then
        osascript -e "tell application \"System Events\" to keystroke \"$esc\" using {$mods}"
      else
        osascript -e "tell application \"System Events\" to keystroke \"$esc\""
      fi
      if [ -n "$KEYLOG" ]; then
        local raw_mods
        raw_mods=$(echo "$action" | jq -r '(.mods // []) | join(",")')
        printf '%s\t%s\n' "$(python3 -c 'import time; print(time.time())')" \
               "$(key_glyphs "$key" "$raw_mods")" >> "$KEYLOG"
      fi
    elif [ -n "$cli" ]; then
      "$READER" "$FIXTURES/$cli"
    elif [ -n "$ms" ]; then
      sleep "$(echo "$ms" | awk '{print $1/1000}')"
    fi
  done
}

assert_dimensions() {
  local file="$1" expect_w="$2" got_w
  got_w=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
  if [ "$got_w" != "$expect_w" ]; then
    echo "capture: '$file' is ${got_w}px wide, expected ${expect_w}px." >&2
    echo "  The window was resized mid-run; layout will jitter between shots." >&2
    exit 8
  fi
}

RAW_DIR=$(mktemp -d)

count=$(jq '.shots | length' "$MANIFEST")
for i in $(seq 0 $((count - 1))); do
  [ "$count" -eq 0 ] && break
  shot=$(jq -c ".shots[$i]" "$MANIFEST")
  id=$(echo "$shot" | jq -r '.id')
  [ -n "$ONLY" ] && [ "$ONLY" != "$id" ] && continue

  # The first shot already has a clean app from the setup above.
  [ "$i" -gt 0 ] && reset_state

  if [ "$(echo "$shot" | jq -r '.manual // false')" = "true" ]; then
    if [ -f "$FINAL_OUT/$id.png" ]; then
      echo "  $id — manual, keeping existing file"
    else
      echo "  $id — MANUAL SHOT MISSING (see references/manual-shots.md)" >&2
    fi
    continue
  fi

  open_path=$(echo "$shot" | jq -r '.open // empty')
  [ -n "$open_path" ] && "$READER" "$FIXTURES/$open_path"
  run_actions "$shot"

  if [ "$(echo "$shot" | jq -r 'has("video")')" = "true" ]; then
    record_video "$shot" "$id"
    continue
  fi

  settle "$WINID" "$RAW_DIR/$id.png"
  assert_dimensions "$RAW_DIR/$id.png" "$((WIN_W * 2))"
  # ffmpeg does the downscale and re-encode: oxipng/pngquant are not installed
  # and ffmpeg is already required for clips.
  ffmpeg -v error -y -i "$RAW_DIR/$id.png" -vf scale=2400:-1 \
         -compression_level 100 "$OUT/$id.png"
  echo "  $id"
done

# --- reproducibility ---------------------------------------------------------
# Byte-equality is deliberately NOT the criterion across runs: Liquid Glass
# samples what is behind the window and PNG encoding is not contractually
# stable, so exact bytes would fail falsely. SSIM below 0.99 means the two runs
# genuinely disagree.
if [ "$VERIFY" -eq 1 ]; then
  echo "capture: verifying reproducibility against $FINAL_OUT"
  fail=0
  for i in $(seq 0 $((count - 1))); do
    [ "$count" -eq 0 ] && break
    shot=$(jq -c ".shots[$i]" "$MANIFEST")
    id=$(echo "$shot" | jq -r '.id')
    [ "$(echo "$shot" | jq -r '.manual // false')" = "true" ] && continue
    [ "$(echo "$shot" | jq -r 'has("video")')" = "true" ] && continue
    if [ ! -f "$FINAL_OUT/$id.png" ]; then
      echo "capture: '$id' has no committed image to compare against" >&2
      fail=1; continue
    fi
    # Fresh capture (in $OUT, a temp dir) vs the committed one.
    score=$(ffmpeg -hide_banner -i "$OUT/$id.png" -i "$FINAL_OUT/$id.png" \
            -filter_complex "ssim=stats_file=-" -f null - 2>/dev/null \
            | awk '{for(j=1;j<=NF;j++) if($j ~ /^All:/){sub("All:","",$j); print $j}}' | head -1)
    [ -n "$score" ] || { echo "capture: could not compare '$id'" >&2; fail=1; continue; }
    ok=$(awk -v s="$score" 'BEGIN{print (s >= 0.99) ? "1" : "0"}')
    if [ "$ok" != "1" ]; then
      echo "capture: '$id' differs between runs (SSIM $score)" >&2
      fail=1
    fi
  done
  rm -rf "$OUT"
  [ "$fail" -eq 0 ] || exit 9
  echo "capture: reproducible"
fi

osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
