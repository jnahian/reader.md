// The docs pages live in the repo's docs/features/, not in web/. The site is
// downstream of the app's own documentation (see web/CLAUDE.md), and rendering
// those files directly means the prose has exactly one copy — mirroring it into
// src/data/ by hand is where drift comes from.
import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

const docs = defineCollection({
  loader: glob({ pattern: "*.md", base: "../docs/features" }),
  schema: z.object({
    title: z.string(),
    order: z.number(),
    summary: z.string(),
  }),
});

export const collections = { docs };
