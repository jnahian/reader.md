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
APP="$REPO/build/$APP_NAME.app"
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
  local i ax
  for i in $(seq 1 80); do
    WINID=$(swift "$HERE/winid.swift" "$APP_NAME" 2>/dev/null | head -1) || WINID=""
    if [ -n "$WINID" ]; then
      # Count only real document windows: the app also exposes an unnamed
      # AXSystemDialog that sorts ahead of it and is NOT what we want to drive.
      ax=$(osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to count of (windows whose value of attribute \"AXSubrole\" is \"AXStandardWindow\")" 2>/dev/null || echo 0)
      [ "${ax:-0}" -ge 1 ] && return 0
    fi
    sleep 0.25
  done
  echo "capture: app window never appeared" >&2
  exit 5
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

seed_prefs
launch_app
set_geometry "$WIN_W" "$WIN_H"
assert_frontmost

echo "capture: $PAGE — window ${WIN_W}x${WIN_H}, fixtures at $FIXTURES"

# Shots are executed in task 5.

osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
