---
name: seo-content
description: Research keywords and write or optimise a search-friendly page for the Reader.md site — use-case pages, feature docs pages, landing copy. Use whenever the user wants a new use-case page, mentions SEO, keywords, search intent, meta descriptions, structured data or schema markup, "rank for", or making pages easier for AI/LLMs to extract — even if they don't say "SEO".
---

# seo-content

One page at a time: a keyword map, then a page built on it. Generic SEO you
already know; this skill is how it lands on **this** site's plumbing, and the
rules that keep it honest.

**Three gates, none auto-approved:**

| # | When | User approves |
|---|------|---------------|
| 1 | Before drafting | The keyword map (and, for a new page type, where it lives) |
| 2 | Before commit | The finished page |
| 3 | Before push | Publishing — anything in `docs/` merged to `main` is live |

## 1. Keyword map, per topic

Load search with `ToolSearch` (`select:WebSearch,WebFetch`). There is no volume
tool. **Never invent search volumes or difficulty scores** — rank by relevance
and intent, and give the reason in one phrase.

For each topic find four buckets:

- **Primary** — the 1–2 terms the page must own ("markdown viewer mac").
- **Long-tail** — specific, low-competition phrasings that match a real job
  ("preview README files before pushing", "read markdown over ssh").
- **Questions** — from People Also Ask, forums, GitHub issues, Reddit
  ("how do I view markdown on mac without an editor").
- **Commercial** — comparison/choice intent ("best markdown viewer for mac",
  "free typora alternative", "marked 2 alternative").

Check the live SERP for each primary: what ranks (docs page, listicle, app
store, forum) is the intent Google has settled on — match it or pick another
term. Competitors worth reading: Typora, MacDown, Marked 2, Obsidian, Quick
Look plugins.

Drop a keyword the app can't truthfully satisfy, however attractive. Present
the map as a table (keyword · bucket · intent · why it fits · target section)
and stop for gate 1.

## 2. Where it lives

- Docs and feature pages: `docs/*.md`, `docs/features/<slug>.md` → `/docs/<slug>`.
  The filename *is* the URL — short, lowercase, hyphenated, primary keyword in it.
- **Use cases**: `docs/use-cases/<slug>.md` → `/use-cases/<slug>`, a separate
  `useCases` collection (`web/src/content.config.ts`) — not under `/docs/`.
  Frontmatter: `title`, `order`, `summary`, optional `related` (docs page ids).
  The `/use-cases` index, nav, `llms.txt` and sitemap pick a new file up with no
  other edit; a link to it from docs is a relative path (`../use-cases/<slug>.md`).
- Any other new page type is the user's call; ask. A new `docs/` subdirectory
  published under `/docs/` needs all three of `DOC_PATTERNS`, `docId` and
  `isDocPage` in `web/plugins/docs-pages.mjs` — `isDocPage`'s regex hardcodes
  `features/`, and missing it silently breaks link rewriting.
- Never put page prose in `web/src/`. The markdown is the only copy.

## 3. Page checklist → where each lives

| Requirement | Here |
|---|---|
| Search title | frontmatter `title`; renders as `<title>{title} — Reader.md</title>` — keep `title` ≤ ~48 chars, primary keyword first |
| Clear H1 | the `# ` line; may be the human phrasing while `title` carries the query phrasing |
| Meta description | frontmatter `summary`, ~150–160 chars — also the og:description, the `/docs` hub card and `llms.txt` line, so it must read as a sentence, not a keyword list |
| H2/H3 | one idea per H2; H3 for questions and sub-steps; headings in the reader's words |
| Internal links | relative `.md` paths (`features/git.md#scope`), rewritten at build; plus `related: [ids]` in frontmatter for the footer. Every new page links to 2+ existing pages and gets linked *from* 1+ |
| Hub placement | `category` + `order`; a category sorts by its lowest `order`, so a low number moves a whole group up the hub |
| Intent match | first screen answers what the SERP showed the searcher wants |

## 4. Section shape: question → answer → context → proof

For the sections that carry a keyword or question:

1. **Question** as the H2/H3, phrased as searched.
2. **Direct answer** — first 1–2 sentences, standalone, no "it" referring
   upward. This is the sentence an AI or a snippet lifts.
3. **Context** — how, when, limits, the shortcut "Label (⌘X)".
4. **Proof** — a real screenshot/clip, a command, a link to the feature doc.

Screenshots come only from a `<slug>.shots.json` manifest captured by the
`reader-docs` skill — never shot by hand. Capture writes to
`docs/assets/screenshots/<page>/` wherever the page lives.

## 5. AI-extractable

- Self-contained paragraphs; name the thing ("Reader.md renders Mermaid…"),
  not "it does".
- Facts as lists or tables, not buried in prose. Exact names for keys, flags,
  file paths in code spans.
- New pages appear in `/llms.txt` automatically — `summary` is the line an
  agent sees first. Docs pages also get a `/docs/<id>.md` twin; use cases don't.

## 6. Structured data

Markdown can't declare it, and **never hand-write JSON-LD in a page**. It is
built in `web/src/pages/docs/[...slug].astro` from frontmatter and passed to
`Base.astro`'s `schema` prop.

- Today only `faq.md` gets `FAQPage` (`rehype-faq-accordion` is scoped to that
  file). Question/answer sections elsewhere produce **no** FAQ schema.
- Use-case pages get `TechArticle` + `BreadcrumbList` from
  `web/src/pages/use-cases/[slug].astro`; the index gets `CollectionPage`.
- The same for docs pages is issue #92. Until it lands, docs pages carry no
  schema — say so; don't claim it.
- Keep `title` and `summary` accurate: they become `headline`/`description`.

## 7. Truth rules

- Claim only behaviour documented in `docs/features/`. Shortcuts are checked
  against the `.keyboardShortcut` bindings in `ReaderMdApp.swift`.
- Comparisons with competitors: factual, current, no disparagement; drop a
  claim you can't source.
- Free, MIT, macOS 13+, Apple silicon only — never imply Intel or Windows.

## 8. Verify and ship

```sh
cd web && npm run build
grep -rho 'href="[^"]*\.md[^"]*"' dist   # only absolute GitHub URLs
```

Check `dist/docs/<slug>/index.html`: one `<h1>`, `<title>`, `<meta name="description">`,
and the JSON-LD if #92 is in. Gate 2, commit, gate 3, then push + `gh pr create`
with the `web` label if `web/` changed.
