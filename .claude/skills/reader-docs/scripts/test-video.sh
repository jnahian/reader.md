#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
REPO=$(git rev-parse --show-toplevel)

cat > /tmp/video.json <<'EOF'
{
  "page": "_test",
  "window": { "width": 1400, "height": 900 },
  "prefs": { "reader.md.folders": ["<fixtures>/field-notes"] },
  "shots": [
    { "id": "01-width",
      "open": "field-notes/guides/setup.md",
      "video": { "seconds": 6 },
      "actions": [
        { "waitMs": 1200 },
        { "key": "\\", "mods": ["shift", "command"] },
        { "waitMs": 1500 },
        { "key": "\\", "mods": ["shift", "command"] },
        { "waitMs": 1500 }
      ],
      "caption": "Cycling the canvas width (⇧⌘\\)" }
  ]
}
EOF

./capture.sh /tmp/video.json || { echo "FAIL: capture exited nonzero"; exit 1; }

mp4="$REPO/docs/assets/screenshots/_test/01-width.mp4"
[ -f "$mp4" ] || { echo "FAIL: missing $mp4"; exit 1; }
[ -f "$REPO/docs/assets/screenshots/_test/01-width.poster.jpg" ] || { echo "FAIL: missing poster"; exit 1; }

w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$mp4")
[ "$w" = "1600" ] || { echo "FAIL: video is ${w}px, expected 1600"; exit 1; }

dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp4")
ok=$(awk -v d="$dur" 'BEGIN{print (d > 4 && d < 8) ? 1 : 0}')
[ "$ok" = "1" ] || { echo "FAIL: duration $dur outside expected range"; exit 1; }

bytes=$(stat -f%z "$mp4")
[ "$bytes" -lt 2000000 ] || { echo "FAIL: clip is ${bytes} bytes, over the 2MB budget"; exit 1; }

rm -rf "$REPO/docs/assets/screenshots/_test"
echo "PASS"
