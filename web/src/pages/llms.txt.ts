// https://llmstxt.org — a plain-text index of the site for language models, so
// an agent gets the page inventory in one fetch instead of crawling the nav.
//
// Built from the docs collection, which is built from plugins/docs-pages.mjs:
// adding a file under the repo's docs/ lists it here with no edit to this file,
// exactly as it appears on the /docs hub. A hand-written list would drift the
// first time a page was added.
import type { APIRoute } from "astro";
import { getCollection } from "astro:content";
import { repo, website, description } from "../data/site";

// Categories appear in the order their lowest-ordered page does — the same rule
// the sidebar sorts by, so the two readings of the docs agree.
const byCategory = (pages: { data: { category: string } }[]) => {
  const groups = new Map<string, typeof pages>();
  for (const page of pages) {
    const group = groups.get(page.data.category);
    if (group) group.push(page);
    else groups.set(page.data.category, [page]);
  }
  return groups;
};

export const GET: APIRoute = async () => {
  const pages = (await getCollection("docs")).sort(
    (a, b) => a.data.order - b.data.order
  );

  const sections = [...byCategory(pages)].map(
    ([category, group]) =>
      `## ${category}\n\n` +
      group
        .map((p) => `- [${p.data.title}](${website}/docs/${p.id}): ${p.data.summary}`)
        .join("\n")
  );

  const body = [
    "# Reader.md",
    "",
    `> ${description}`,
    "",
    "Reader.md is a free, MIT-licensed native macOS app — a reader, not an editor.",
    "It needs macOS 13 or later on an Apple-silicon Mac. Everything renders locally;",
    "the only network access is the auto-update check.",
    "",
    ...sections.flatMap((s) => [s, ""]),
    "## Optional",
    "",
    `- [Home](${website}/): what the app is, with screenshots.`,
    `- [Changelog](${website}/changelog): what shipped in each release.`,
    `- [Source](${repo}): the repository, issue tracker and releases.`,
    "",
  ].join("\n");

  return new Response(body, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
};
