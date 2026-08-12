// Pages reference assets by their true on-disk relative path
// (../assets/screenshots/<page>/<id>.png) so they render correctly in Reader.md
// itself and on GitHub. On the site those files are served from /screenshots/,
// so rewrite the prefix at build time.
//
// Markdown has no video syntax, so a clip is written with image syntax and
// swapped to a <video> element here.
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { visit } from "unist-util-visit";

const PREFIX = /^\.\.\/assets\/screenshots\//;

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
  return (tree) => {
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
