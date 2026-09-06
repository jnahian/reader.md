// @ts-check
import { rename } from "node:fs/promises";
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import { rehypeHeadingIds } from "@astrojs/markdown-remark";
import { remarkDocsAssets } from "./plugins/remark-docs-assets.mjs";
import { rehypeFaqAccordion } from "./plugins/rehype-faq-accordion.mjs";

// https://astro.build/config
export default defineConfig({
  site: "https://reader-md.jnahian.me",
  // Every page is static and listed here; robots.txt points crawlers at it.
  // 404 is excluded by the integration itself.
  integrations: [
    sitemap(),
    // The integration hard-codes `<filenameBase>-index.xml`, but /sitemap.xml is
    // the name a crawler guesses. Renaming the index rather than the chunk keeps
    // the split: sitemap.xml stays an index over sitemap-0.xml, so a site that
    // outgrew one chunk would still be described correctly.
    {
      name: "sitemap-at-the-conventional-name",
      hooks: {
        "astro:build:done": ({ dir }) =>
          rename(new URL("sitemap-index.xml", dir), new URL("sitemap.xml", dir)),
      },
    },
  ],
  markdown: {
    remarkPlugins: [remarkDocsAssets],
    // rehypeHeadingIds is listed explicitly so it runs before the accordion
    // plugin: the FAQ's deep links need the h3 ids to already be assigned.
    rehypePlugins: [rehypeHeadingIds, rehypeFaqAccordion],
  },
  vite: {
    server: {
      // The docs collection reads ../docs/features, outside the Astro root.
      // Builds read through Node directly; only `astro dev` needs this.
      fs: { allow: [".."] },
    },
  },
});
