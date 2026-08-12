// The docs pages live in the repo's docs/, not in web/. The site is downstream
// of the app's own documentation (see web/CLAUDE.md), and rendering those files
// directly means the prose has exactly one copy — mirroring it into src/data/
// by hand is where drift comes from.
import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";
import { DOC_PATTERNS, docId } from "../plugins/docs-pages.mjs";

// Flattening features/<name>.md onto /docs/<name> can collide: a future
// features/cli.md would land on the same URL as cli.md. Fail the build there
// rather than let one page silently replace the other in the grid.
const claimed = new Map<string, string>();
const generateId = ({ entry }: { entry: string }) => {
  const id = docId(entry);
  const prev = claimed.get(id);
  if (prev && prev !== entry) {
    throw new Error(
      `docs collection: "${entry}" and "${prev}" both publish at /docs/${id}`
    );
  }
  claimed.set(id, entry);
  return id;
};

const docs = defineCollection({
  loader: glob({ pattern: DOC_PATTERNS, base: "../docs", generateId }),
  schema: z.object({
    title: z.string(),
    // Groups the page on the /docs hub and in the sidebar. Pages sort by
    // `order` globally; a category's position follows its lowest-ordered page.
    category: z.string(),
    order: z.number(),
    summary: z.string(),
    // Ids of pages to offer at the foot of this one. Ids, not URLs, so a
    // renamed or missing page fails the build instead of shipping a dead link.
    related: z.array(z.string()).optional(),
  }),
});

export const collections = { docs };
