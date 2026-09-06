// The markdown behind every docs page, at the page's own URL plus `.md`:
// /docs/reading is the page, /docs/reading.md is what it was rendered from.
// Agents and LLMs get the source instead of parsing the HTML back into prose,
// and the "Copy .md" button on each page fetches its own twin.
//
// The body is served verbatim except for its links, which are written as
// on-disk relative paths (`../cli.md`) so they resolve in Reader.md and on
// GitHub. Those paths don't survive being flattened onto /docs/, so they are
// resolved to absolute URLs here — through the same rewriteLink the rendered
// page uses, so a link can't mean two different things.
import type { APIRoute } from "astro";
import { getCollection, type CollectionEntry } from "astro:content";
import { rewriteLink } from "../../../plugins/remark-docs-assets.mjs";
import { website } from "../../data/site";

const SCREENSHOTS = /^\.\.\/assets\/screenshots\//;

// Every destination in docs/ is a plain inline `](target)` — no titles, no
// reference definitions — so this doesn't need a markdown parser, and not
// having one is why the rest of the file survives byte for byte.
const absolutize = (body: string, from: string) =>
  body.replace(/\]\(([^)]+)\)/g, (whole, dest: string) => {
    if (SCREENSHOTS.test(dest)) {
      return `](${website}${dest.replace(SCREENSHOTS, "/screenshots/")})`;
    }
    const rewritten = rewriteLink(dest, from);
    // Absolute URLs, site-absolute paths and bare fragments come back null:
    // they are already right, in markdown as much as in HTML.
    if (!rewritten) return whole;
    // A sibling docs page points at that page's markdown, so following a link
    // out of one .md lands in another rather than back in the HTML.
    const doc = rewritten.match(/^\/docs\/([^#]+)(#.*)?$/);
    return `](${doc ? `${website}/docs/${doc[1]}.md${doc[2] ?? ""}` : rewritten})`;
  });

export async function getStaticPaths() {
  const pages = await getCollection("docs");
  return pages.map((page) => ({ params: { slug: page.id }, props: { page } }));
}

export const GET: APIRoute = ({ props }) => {
  const { page } = props as { page: CollectionEntry<"docs"> };
  return new Response(absolutize(page.body ?? "", page.filePath ?? ""), {
    headers: { "Content-Type": "text/markdown; charset=utf-8" },
  });
};
