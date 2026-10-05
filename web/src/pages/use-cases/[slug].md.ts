// The markdown behind every use case, at the page's own URL plus `.md` — the
// same twin the docs pages have (see pages/docs/[slug].md.ts).
import type { APIRoute } from "astro";
import { getCollection, type CollectionEntry } from "astro:content";
import { absolutize } from "../../lib/markdown-twin";

export async function getStaticPaths() {
  const pages = await getCollection("useCases");
  return pages.map((page) => ({ params: { slug: page.id }, props: { page } }));
}

export const GET: APIRoute = ({ props }) => {
  const { page } = props as { page: CollectionEntry<"useCases"> };
  return new Response(absolutize(page.body ?? "", page.filePath ?? ""), {
    headers: { "Content-Type": "text/markdown; charset=utf-8" },
  });
};
