// Pages reference assets by their true on-disk relative path
// (../assets/screenshots/<page>/<id>.png) so they render correctly in Reader.md
// itself and on GitHub. On the site those files are served from /screenshots/,
// so rewrite the prefix at build time.
//
// Markdown has no video syntax, so a clip is written with image syntax and
// swapped to a <video> element here.
//
// Links between docs files are written as real relative paths for the same
// reason, and are rewritten here too: to another docs page if it publishes, and
// otherwise to the file on GitHub.
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { visit } from "unist-util-visit";
import { docId, isDocPage } from "./docs-pages.mjs";

const PREFIX = /^\.\.\/assets\/screenshots\//;

// Resolved from web/, which is the cwd for both `astro dev` and `astro build`.
const REPO_ROOT = path.resolve("..");
const DOCS_DIR = path.join(REPO_ROOT, "docs");
const BLOB = "https://github.com/jnahian/reader.md/blob/main/";

// Absolute URLs, site-absolute paths, and bare fragments are already correct.
const ABSOLUTE = /^(?:[a-z][a-z0-9+.-]*:|\/|#)/i;

function rewriteLink(url, from) {
  if (!from || ABSOLUTE.test(url)) return null;
  const cut = url.indexOf("#");
  const target = cut === -1 ? url : url.slice(0, cut);
  const hash = cut === -1 ? "" : url.slice(cut);
  if (!target) return null;

  const abs = path.resolve(path.dirname(from), target);
  const inDocs = path.relative(DOCS_DIR, abs);
  if (!inDocs.startsWith("..") && isDocPage(inDocs)) {
    return `/docs/${docId(inDocs)}${hash}`;
  }
  return `${BLOB}${path.relative(REPO_ROOT, abs)}${hash}`;
}

// Real pixel dimensions, so a full-width media slot does not collapse and
// reflow the page while it loads. Read once per asset and cached — a page has
// a handful of assets and the build should not shell out repeatedly.
const ASSET_ROOT = path.resolve("../docs/assets/screenshots");
const dimCache = new Map();

function dimensions(src) {
  if (dimCache.has(src)) return dimCache.get(src);
  const file = path.join(ASSET_ROOT, src.replace(/^\/screenshots\//, ""));
  let dim = null;
  if (existsSync(file)) {
    try {
      const out = execFileSync(
        "ffprobe",
        ["-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", file],
        { encoding: "utf8" }
      ).trim();
      const [w, h] = out.split("x").map(Number);
      if (w > 0 && h > 0) dim = { w, h };
    } catch {
      // ffprobe missing or unreadable asset: fall through without dimensions
      // rather than failing the build.
    }
  }
  dimCache.set(src, dim);
  return dim;
}

const sizeAttrs = (src) => {
  const d = dimensions(src);
  return d ? ` width="${d.w}" height="${d.h}"` : "";
};

const escapeAttr = (s) => String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;");
const escapeText = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export function remarkDocsAssets() {
  return (tree, file) => {
    visit(tree, "link", (node) => {
      const url = rewriteLink(node.url, file?.path);
      if (url) node.url = url;
    });

    visit(tree, "image", (node, index, parent) => {
      if (!PREFIX.test(node.url) || parent == null || index == null) return;
      const src = node.url.replace(PREFIX, "/screenshots/");
      const caption = node.alt ?? "";

      if (!src.endsWith(".mp4")) {
        parent.children[index] = {
          type: "html",
          value:
            `<figure class="docs-media">` +
            `<img src="${escapeAttr(src)}" alt="${escapeAttr(caption)}"` +
            `${sizeAttrs(src)} loading="lazy" decoding="async" />` +
            `<figcaption>${escapeText(caption)}</figcaption></figure>`,
        };
        return;
      }

      const poster = src.replace(/\.mp4$/, ".poster.jpg");
      parent.children[index] = {
        type: "html",
        value:
          `<figure class="docs-media docs-media--video">` +
          `<video src="${escapeAttr(src)}" poster="${escapeAttr(poster)}"` +
          `${sizeAttrs(src)} autoplay loop muted playsinline preload="metadata" ` +
          `aria-label="${escapeAttr(caption)}"></video>` +
          `<figcaption>${escapeText(caption)}</figcaption></figure>`,
      };
    });
  };
}
