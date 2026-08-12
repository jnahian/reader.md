// @ts-check
import { defineConfig } from "astro/config";
import { remarkDocsAssets } from "./plugins/remark-docs-assets.mjs";

// https://astro.build/config
export default defineConfig({
  site: "https://reader-md.jnahian.me",
  markdown: {
    remarkPlugins: [remarkDocsAssets],
  },
  vite: {
    server: {
      // The docs collection reads ../docs/features, outside the Astro root.
      // Builds read through Node directly; only `astro dev` needs this.
      fs: { allow: [".."] },
    },
  },
});
