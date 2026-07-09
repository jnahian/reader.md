// Copies the app's bundled docs into src/generated/ so Astro pages can
// import them without reaching outside the site root at build time.
import { copyFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.resolve(here, "../../Sources/ReaderMd/Resources/docs");
const outDir = path.resolve(here, "../src/generated");

mkdirSync(outDir, { recursive: true });
for (const name of ["CHANGELOG.md", "FAQ.md", "SHORTCUTS.md"]) {
  copyFileSync(path.join(srcDir, name), path.join(outDir, name)); // throws → build fails loudly
}
console.log("copy-docs: 3 files → src/generated/");
