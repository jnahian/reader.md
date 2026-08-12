# Vendored from coreyhaines31/marketingskills

- Upstream: https://github.com/coreyhaines31/marketingskills (MIT — see `LICENSE-upstream`)
- Commit: 7868cb9251fad80a73d26e488a5ad5f6c4a9f335
- Date: 2026-07-27
- Skills: product-marketing copy-editing
- Local modifications: each SKILL.md `description:` is prefixed with
  "Internal writing aid for reader-docs; invoked explicitly by its
  orchestrator, not auto-triggered." Content is otherwise unmodified.

## Why only these two

`product-marketing` produces `.agents/product-marketing.md` — audience,
positioning, and the vocabulary users actually use. It writes no page content;
reader-docs reads it as shared context so every page describes the same product
to the same reader.

`copy-editing` is a polish pass built on focused edits rather than rewrites,
and its `references/plain-english-alternatives.md` applies directly to
documentation.

The upstream set also has `copywriting`, `content-strategy`, and `ai-seo`.
They target conversion pages and search traffic, and their framing fights
`references/voice.md`, which bans marketing adjectives. Not vendored.

## Updating

```bash
./scripts/vendor-skills.sh          # latest upstream main
./scripts/vendor-skills.sh <sha>    # pin a specific commit
```

Re-read `references/voice.md` after an update: if upstream guidance starts
contradicting it, voice.md wins and the conflict should be noted there.
