// Which files under the repo's docs/ publish as site pages, and the URL each
// one gets. Imported by src/content.config.ts (to build the collection) and by
// remark-docs-assets.mjs (to rewrite the links between them), so the two views
// of "what is a docs page" cannot drift.
//
// Paths here are relative to the repo's docs/ directory.
//
// markup-model.md is absent on purpose: it is a design sketch for unshipped
// work, so it stays a repo document and links to it fall through to GitHub.

export const DOC_PATTERNS = [
  "install.md",
  "features.md",
  "features/*.md",
  "cli.md",
  "architecture.md",
  "building.md",
];

// features/reading.md publishes at /docs/reading. The directory is a source
// convention — one file per feature area — not part of the URL.
export const docId = (docsRelPath) =>
  docsRelPath.replace(/^features\//, "").replace(/\.md$/, "");

const EXACT = new Set(DOC_PATTERNS.filter((p) => !p.includes("*")));

export const isDocPage = (docsRelPath) =>
  EXACT.has(docsRelPath) || /^features\/[^/]+\.md$/.test(docsRelPath);
