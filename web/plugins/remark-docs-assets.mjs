// Pages reference assets by their true on-disk relative path
// (../assets/screenshots/<page>/<id>.png) so they render correctly in Reader.md
// itself and on GitHub. On the site those files are served from /screenshots/,
// so rewrite the prefix at build time.
//
// Markdown has no video syntax, so a clip is written with image syntax and
// swapped to a <video> element here.
import { visit } from "unist-util-visit";

const PREFIX = /^\.\.\/assets\/screenshots\//;

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
            `<img src="${escapeAttr(src)}" alt="${escapeAttr(caption)}" ` +
            `loading="lazy" decoding="async" />` +
            `<figcaption>${escapeText(caption)}</figcaption></figure>`,
        };
        return;
      }

      const poster = src.replace(/\.mp4$/, ".poster.jpg");
      parent.children[index] = {
        type: "html",
        value:
          `<figure class="docs-media docs-media--video">` +
          `<video src="${escapeAttr(src)}" poster="${escapeAttr(poster)}" ` +
          `autoplay loop muted playsinline preload="metadata" ` +
          `aria-label="${escapeAttr(caption)}"></video>` +
          `<figcaption>${escapeText(caption)}</figcaption></figure>`,
      };
    });
  };
}
