// @ts-check
import { defineConfig } from "astro/config";
import { rehypeHeadingIds } from "@astrojs/markdown-remark";
import { remarkDocsAssets } from "./plugins/remark-docs-assets.mjs";
import { rehypeFaqAccordion } from "./plugins/rehype-faq-accordion.mjs";

// https://astro.build/config
export default defineConfig({
  site: "https://reader-md.jnahian.me",
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
