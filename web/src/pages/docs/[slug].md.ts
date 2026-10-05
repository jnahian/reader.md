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
import { absolutize } from "../../lib/markdown-twin";

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
