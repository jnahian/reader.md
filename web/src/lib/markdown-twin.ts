// Shared by the .md twins of docs pages and use cases: resolves the on-disk
// relative links a page is written with to absolute URLs, through the same
// rewriteLink the rendered page uses, so a link can't mean two things.
import { rewriteLink } from "../../plugins/remark-docs-assets.mjs";
import { website } from "../data/site";

const SCREENSHOTS = /^\.\.\/assets\/screenshots\//;

// Every destination in docs/ is a plain inline `](target)` — no titles, no
// reference definitions — so this doesn't need a markdown parser, and not
// having one is why the rest of the file survives byte for byte.
export const absolutize = (body: string, from: string) =>
  body.replace(/\]\(([^)]+)\)/g, (whole, dest: string) => {
    if (SCREENSHOTS.test(dest)) {
      return `](${website}${dest.replace(SCREENSHOTS, "/screenshots/")})`;
    }
    const rewritten = rewriteLink(dest, from);
    // Absolute URLs, site-absolute paths and bare fragments come back null:
    // they are already right, in markdown as much as in HTML.
    if (!rewritten) return whole;
    // A docs page or use case points at that page's markdown, so following a
    // link out of one .md lands in another rather than back in the HTML.
    const page = rewritten.match(/^\/(docs|use-cases)\/([^#]+)(#.*)?$/);
    if (page) return `](${website}/${page[1]}/${page[2]}.md${page[3] ?? ""})`;
    return `](${rewritten})`;
  });
