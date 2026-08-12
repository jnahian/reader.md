#!/bin/bash
# Vendors the writing skills reader-docs depends on from coreyhaines31/marketingskills
# (MIT). Pins to a commit and records it in vendored/VERSIONS.md.
#
#   ./vendor-skills.sh          # latest upstream main
#   ./vendor-skills.sh <sha>    # a specific commit
#
# Only two skills are vendored. The upstream set also has copywriting,
# content-strategy, and ai-seo, which optimise for conversion and search
# traffic — they pull against the plain, unhedged voice these docs use, and
# vendoring the whole set pollutes skill triggering.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$(cd "$HERE/.." && pwd)/vendored"
UPSTREAM="https://github.com/coreyhaines31/marketingskills"
SKILLS=(product-marketing copy-editing)

REF="${1:-main}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Cloning $UPSTREAM …"
git clone -q "$UPSTREAM" "$TMP/repo"
git -C "$TMP/repo" checkout -q "$REF"
SHA=$(git -C "$TMP/repo" rev-parse HEAD)
DATE=$(git -C "$TMP/repo" show -s --format=%cs HEAD)

mkdir -p "$DEST"
for s in "${SKILLS[@]}"; do
  [ -d "$TMP/repo/skills/$s" ] || { echo "vendor: upstream has no skill '$s'" >&2; exit 1; }
  rm -rf "${DEST:?}/$s"
  cp -R "$TMP/repo/skills/$s" "$DEST/$s"
  # Upstream descriptions are broad ("when the user wants to write marketing
  # copy") and would auto-fire on unrelated work in this repo. reader-docs
  # invokes these explicitly, so mark them as internal.
  /usr/bin/sed -i '' \
    's|^description: "|description: "Internal writing aid for reader-docs; invoked explicitly by its orchestrator, not auto-triggered. |' \
    "$DEST/$s/SKILL.md"
  echo "  vendored $s"
done

cp "$TMP/repo/LICENSE" "$DEST/LICENSE-upstream" 2>/dev/null || true

cat > "$DEST/VERSIONS.md" <<EOF
# Vendored from coreyhaines31/marketingskills

- Upstream: $UPSTREAM (MIT — see \`LICENSE-upstream\`)
- Commit: $SHA
- Date: $DATE
- Skills: ${SKILLS[*]}
- Local modifications: each SKILL.md \`description:\` is prefixed with
  "Internal writing aid for reader-docs; invoked explicitly by its
  orchestrator, not auto-triggered." Content is otherwise unmodified.

## Why only these two

\`product-marketing\` produces \`.agents/product-marketing.md\` — audience,
positioning, and the vocabulary users actually use. It writes no page content;
reader-docs reads it as shared context so every page describes the same product
to the same reader.

\`copy-editing\` is a polish pass built on focused edits rather than rewrites,
and its \`references/plain-english-alternatives.md\` applies directly to
documentation.

The upstream set also has \`copywriting\`, \`content-strategy\`, and \`ai-seo\`.
They target conversion pages and search traffic, and their framing fights
\`references/voice.md\`, which bans marketing adjectives. Not vendored.

## Updating

\`\`\`bash
./scripts/vendor-skills.sh          # latest upstream main
./scripts/vendor-skills.sh <sha>    # pin a specific commit
\`\`\`

Re-read \`references/voice.md\` after an update: if upstream guidance starts
contradicting it, voice.md wins and the conflict should be noted there.
EOF

echo "Pinned $SHA ($DATE) → $DEST"
