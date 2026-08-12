#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
REPO=$(git rev-parse --show-toplevel)

cat > /tmp/stills.json <<'EOF'
{
  "page": "_test",
  "window": { "width": 1400, "height": 900 },
  "prefs": { "reader.md.folders": ["<fixtures>/field-notes"] },
  "shots": [
    { "id": "01-empty", "caption": "Empty state" },
    { "id": "02-doc",
      "open": "field-notes/guides/architecture.md",
      "caption": "A rendered document" },
    { "id": "03-outline",
      "open": "field-notes/guides/setup.md",
      "actions": [ { "key": "b", "mods": ["shift", "command"] } ],
      "caption": "Outline open" }
  ]
}
EOF

./capture.sh /tmp/stills.json || { echo "FAIL: capture exited nonzero"; exit 1; }

for id in 01-empty 02-doc 03-outline; do
  f="$REPO/docs/assets/screenshots/_test/$id.png"
  [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  [ "$w" = "2400" ] || { echo "FAIL: $id is ${w}px, expected 2400"; exit 1; }
done

# The Mermaid/KaTeX document must be fully rendered, not caught mid-layout.
# A half-rendered capture is much smaller than a complete one.
size=$(stat -f%z "$REPO/docs/assets/screenshots/_test/02-doc.png")
[ "$size" -gt 100000 ] || { echo "FAIL: 02-doc looks unrendered ($size bytes)"; exit 1; }

./capture.sh /tmp/stills.json --verify-repro || { echo "FAIL: not reproducible"; exit 1; }

rm -rf "$REPO/docs/assets/screenshots/_test"
echo "PASS"
