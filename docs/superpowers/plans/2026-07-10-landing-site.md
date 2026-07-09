# Reader.md Landing Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A static Astro + Tailwind marketing site in `site/` with a landing page and three markdown-backed doc pages (/changelog, /faq, /shortcuts), deployable to Vercel/Netlify.

**Architecture:** Multi-page static Astro site. A prebuild script copies the app's bundled markdown docs into `site/src/generated/` so pages import them as Astro markdown. All theme colors are CSS variables (light + dark via `prefers-color-scheme`) exposed to Tailwind through `@theme inline`. Zero client-side JavaScript.

**Tech Stack:** Astro 5 (static output), Tailwind CSS v4 via `@tailwindcss/vite`, Node 24 / npm 11.

**Spec:** `docs/superpowers/specs/2026-07-10-landing-page-design.md`

## Global Constraints

- **No gradients anywhere** — no `linear-gradient` / `radial-gradient` / `conic-gradient` in any CSS, and no Tailwind `bg-gradient-*` / `from-* / via-* / to-*` utilities.
- **No client JS** — no `<script>` tags, no framework islands.
- **Dark mode:** system `prefers-color-scheme` only, no toggle. Every surface must look right in both schemes.
- **Fonts:** system stack only — sans: `-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif`; mono: `ui-monospace, "SF Mono", Menlo, monospace`. No webfonts.
- **Markdown sources (read-only, never edit):** `Sources/ReaderMd/Resources/docs/CHANGELOG.md`, `FAQ.md`, `SHORTCUTS.md`. `site/src/generated/` is gitignored build output.
- **Download URL (no version baked in):** `https://github.com/jnahian/reader.md/releases/latest/download/Reader.md.dmg`
- **Repo URL:** `https://github.com/jnahian/reader.md`
- All site code lives under `site/`; do not touch app sources except reading them.
- Run all npm commands from `/Users/nahian/Projects/reader.md/site`.
- Shortcut data comes from `SHORTCUTS.md` (v1.6.0 bindings: ⌘F = Find in Page, ⇧⌘F = Filter Files) — the README table is stale, don't copy from it.

---

### Task 1: Scaffold Astro project with Tailwind in `site/`

**Files:**
- Create: `site/` (scaffolded: `package.json`, `astro.config.mjs`, `tsconfig.json`, `.gitignore`, `src/`, `public/`)
- Delete: scaffolded `src/pages/index.astro` content is replaced later; delete template extras (`src/assets/`, `src/components/Welcome.astro`, `src/layouts/Layout.astro`) if the template created them

**Interfaces:**
- Produces: a building Astro project where `npm run build` outputs `site/dist/`, with Tailwind v4 wired through `@tailwindcss/vite` and `src/styles/global.css` containing `@import "tailwindcss";`

- [ ] **Step 1: Scaffold**

```bash
cd /Users/nahian/Projects/reader.md
npm create astro@latest site -- --template minimal --install --no-git --yes
```

Expected: `site/` created, dependencies installed. (If the CLI still asks anything, accept defaults; do NOT initialize git — the repo root already is one.)

- [ ] **Step 2: Add Tailwind v4**

```bash
cd site
npx astro add tailwind --yes
```

Expected: `@tailwindcss/vite` added to `astro.config.mjs` `vite.plugins`, `tailwindcss` in `package.json`, and a CSS file with `@import "tailwindcss";` created (the integration creates `src/styles/global.css`; if it made a different file, rename it to `src/styles/global.css`).

- [ ] **Step 3: Clean template leftovers and stub the index**

Delete template extras (only those that exist):

```bash
rm -rf src/assets src/components/Welcome.astro src/layouts/Layout.astro
```

Replace `site/src/pages/index.astro` with a stub that imports the global CSS (proves Tailwind works):

```astro
---
import "../styles/global.css";
---

<h1 class="text-3xl font-bold">Reader.md site scaffold</h1>
```

- [ ] **Step 4: Verify build**

```bash
npm run build
```

Expected: `✓ Completed` / build finishes with `dist/index.html` generated, no errors.

- [ ] **Step 5: Check .gitignore covers build output**

`site/.gitignore` must contain `node_modules`, `dist`, and add a line for generated docs:

```
# generated markdown copies (see scripts/copy-docs.mjs)
src/generated/
```

- [ ] **Step 6: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add site
git commit -m "feat(site): scaffold Astro + Tailwind v4 project

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Prebuild doc-copy script

**Files:**
- Create: `site/scripts/copy-docs.mjs`
- Modify: `site/package.json` (add `predev`/`prebuild` scripts)

**Interfaces:**
- Produces: `site/src/generated/CHANGELOG.md`, `site/src/generated/FAQ.md`, `site/src/generated/SHORTCUTS.md` — later tasks import these as `import { Content } from "../generated/<NAME>.md"`. Script exits non-zero if any source file is missing.

- [ ] **Step 1: Write the script**

`site/scripts/copy-docs.mjs`:

```js
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
```

- [ ] **Step 2: Wire into npm lifecycle**

In `site/package.json` `"scripts"`, add:

```json
"predev": "node scripts/copy-docs.mjs",
"prebuild": "node scripts/copy-docs.mjs",
```

- [ ] **Step 3: Verify success path**

```bash
cd site
rm -rf src/generated
npm run build
ls src/generated
```

Expected: build passes; `ls` shows `CHANGELOG.md FAQ.md SHORTCUTS.md`.

- [ ] **Step 4: Verify failure path (loud, non-zero)**

```bash
SRC=../Sources/ReaderMd/Resources/docs/CHANGELOG.md
mv $SRC $SRC.bak && (node scripts/copy-docs.mjs; echo exit=$?); mv $SRC.bak $SRC
```

Expected: `ENOENT` error and `exit=1` while the file is moved away; file restored after. (Run from `site/`.)

- [ ] **Step 5: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add site/scripts/copy-docs.mjs site/package.json
git commit -m "feat(site): prebuild script copies bundled docs into src/generated

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Theme tokens, Base layout, icon

**Files:**
- Modify: `site/src/styles/global.css`
- Create: `site/src/layouts/Base.astro`
- Create: `site/public/icon.png` (from `Sources/ReaderMd/Resources/AppIcon.png`)
- Modify: `site/src/pages/index.astro` (use Base)

**Interfaces:**
- Produces: `Base.astro` with props `{ title: string; description?: string }`, rendering nav + `<slot />` + footer. Tailwind color utilities available everywhere: `bg-bg`, `bg-bg-alt`, `bg-card`, `text-fg`, `text-muted`, `bg-accent`, `text-accent`, `text-accent-fg`, `border-border`, `bg-code-bg`, `text-code-fg`, `bg-kbd`. Fonts: `font-sans` (default on body), `font-mono`.

- [ ] **Step 1: Resize icon**

```bash
cd /Users/nahian/Projects/reader.md
sips -Z 512 Sources/ReaderMd/Resources/AppIcon.png --out site/public/icon.png
```

Expected: `site/public/icon.png` exists, 512×512.

- [ ] **Step 2: Theme tokens in global.css**

Replace `site/src/styles/global.css` with:

```css
@import "tailwindcss";

:root {
  --bg: #ffffff;
  --bg-alt: #f5f5f7;
  --card: #ffffff;
  --fg: #1d1d1f;
  --muted: #6e6e73;
  --accent: #0a84ff;
  --accent-fg: #ffffff;
  --border: #d2d2d7;
  --code-bg: #1d1d1f;
  --code-fg: #f5f5f7;
  --kbd: #ececf0;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #101014;
    --bg-alt: #1a1a20;
    --card: #1e1e24;
    --fg: #f5f5f7;
    --muted: #98989f;
    --border: #33333b;
    --code-bg: #060608;
    --code-fg: #e8e8ed;
    --kbd: #2a2a32;
  }
}

@theme inline {
  --color-bg: var(--bg);
  --color-bg-alt: var(--bg-alt);
  --color-card: var(--card);
  --color-fg: var(--fg);
  --color-muted: var(--muted);
  --color-accent: var(--accent);
  --color-accent-fg: var(--accent-fg);
  --color-border: var(--border);
  --color-code-bg: var(--code-bg);
  --color-code-fg: var(--code-fg);
  --color-kbd: var(--kbd);
  --font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
  --font-mono: ui-monospace, "SF Mono", Menlo, monospace;
}
```

(`@theme inline` keeps utilities pointing at the live CSS variables, so dark mode swaps automatically — no `dark:` variants needed for theme colors.)

- [ ] **Step 3: Base layout**

`site/src/layouts/Base.astro`:

```astro
---
import "../styles/global.css";

interface Props {
  title: string;
  description?: string;
}

const {
  title,
  description = "Reader.md is a fast, native macOS markdown reader with live reload, Mermaid, LaTeX, and remote SSH folders.",
} = Astro.props;

const repo = "https://github.com/jnahian/reader.md";
const nav = [
  { href: "/#features", label: "Features" },
  { href: "/#install", label: "Install" },
  { href: "/shortcuts", label: "Shortcuts" },
  { href: "/faq", label: "FAQ" },
  { href: "/changelog", label: "Changelog" },
];
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title}</title>
    <meta name="description" content={description} />
    <link rel="icon" href="/icon.png" />
    <meta property="og:title" content={title} />
    <meta property="og:description" content={description} />
    <meta property="og:image" content="/icon.png" />
  </head>
  <body class="bg-bg font-sans text-fg antialiased">
    <header class="border-b border-border">
      <nav class="mx-auto flex max-w-5xl items-center gap-6 px-6 py-4 text-sm">
        <a href="/" class="flex items-center gap-2 font-semibold">
          <img src="/icon.png" alt="" width="24" height="24" />
          Reader.md
        </a>
        <div class="ml-auto flex flex-wrap items-center gap-5 text-muted">
          {nav.map((item) => (
            <a href={item.href} class="hover:text-fg">{item.label}</a>
          ))}
          <a href={repo} class="hover:text-fg">GitHub</a>
        </div>
      </nav>
    </header>
    <main>
      <slot />
    </main>
    <footer class="border-t border-border py-12 text-center text-sm text-muted">
      <p>
        MIT © Julkar Naen Nahian ·
        <a href={repo} class="underline hover:text-fg">GitHub</a> ·
        <a href={`${repo}/releases`} class="underline hover:text-fg">Releases</a>
      </p>
    </footer>
  </body>
</html>
```

- [ ] **Step 4: Point index at Base**

`site/src/pages/index.astro`:

```astro
---
import Base from "../layouts/Base.astro";
---

<Base title="Reader.md — a native markdown reader for macOS">
  <p class="p-10">sections land in Tasks 4–6</p>
</Base>
```

- [ ] **Step 5: Verify**

```bash
cd site && npm run build && npm run preview
```

Expected: build passes. Load `http://localhost:4321/` in a browser: nav with icon + links, footer, correct colors; toggle system dark mode (or emulate `prefers-color-scheme: dark`) and confirm dark palette applies.

- [ ] **Step 6: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add site
git commit -m "feat(site): theme tokens, base layout, app icon

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Hero + AppMock

**Files:**
- Create: `site/src/components/Hero.astro`
- Create: `site/src/components/AppMock.astro`
- Modify: `site/src/pages/index.astro`

**Interfaces:**
- Consumes: `Base.astro`, theme utilities from Task 3.
- Produces: `<Hero />` and `<AppMock />` (no props).

- [ ] **Step 1: Hero**

`site/src/components/Hero.astro`:

```astro
---
const dmg = "https://github.com/jnahian/reader.md/releases/latest/download/Reader.md.dmg";
const repo = "https://github.com/jnahian/reader.md";
---

<section class="px-6 pb-16 pt-24 text-center">
  <img src="/icon.png" alt="Reader.md app icon" width="128" height="128" class="mx-auto" />
  <h1 class="mt-4 text-5xl font-bold tracking-tight">Reader.md</h1>
  <p class="mx-auto mt-3 max-w-xl text-xl text-muted">
    A fast, native markdown reader for your Mac. Point it at your notes, docs,
    or an entire repo — and just read.
  </p>
  <div class="mt-8 flex flex-wrap justify-center gap-3">
    <a
      href={dmg}
      class="rounded-full bg-accent px-6 py-3 font-medium text-accent-fg hover:opacity-90"
    >Download for Mac</a>
    <a
      href={repo}
      class="rounded-full border border-border px-6 py-3 font-medium hover:bg-bg-alt"
    >View on GitHub</a>
  </div>
  <p class="mt-4 text-sm text-muted">
    Free &amp; open source · macOS 13+ · Apple silicon · Auto-updates via Sparkle
  </p>
</section>
```

- [ ] **Step 2: AppMock**

`site/src/components/AppMock.astro`:

```astro
<div
  class="mx-auto mb-20 max-w-3xl overflow-hidden rounded-xl border border-border bg-card text-xs shadow-2xl"
  aria-hidden="true"
>
  <div class="flex items-center gap-2 border-b border-border bg-bg-alt px-3.5 py-2.5">
    <span class="size-2.5 rounded-full bg-[#ff5f57]"></span>
    <span class="size-2.5 rounded-full bg-[#febc2e]"></span>
    <span class="size-2.5 rounded-full bg-[#28c840]"></span>
    <span class="flex-1 text-center font-medium text-muted">README.md — Reader.md</span>
  </div>
  <div class="flex min-h-80">
    <div class="w-44 shrink-0 border-r border-border bg-bg-alt p-3 text-muted">
      <div class="mb-1.5 mt-2 text-[10px] tracking-widest">FOLDERS</div>
      <div class="truncate rounded-md px-2 py-1">▸ my-notes</div>
      <div class="truncate rounded-md px-2 py-1">▾ project-docs</div>
      <div class="truncate rounded-md bg-accent px-2 py-1 pl-5 text-accent-fg">README.md</div>
      <div class="truncate rounded-md px-2 py-1 pl-5">architecture.md</div>
      <div class="truncate rounded-md px-2 py-1 pl-5">changelog.md</div>
      <div class="truncate rounded-md px-2 py-1">▸ vps-server ☁︎</div>
    </div>
    <div class="min-w-0 flex-1 px-7 py-6">
      <h3 class="mb-2.5 text-xl font-semibold">Getting Started</h3>
      <p class="mb-2.5 text-muted">
        Everything renders natively — code, diagrams, and math included.
      </p>
      <div
        class="overflow-x-auto rounded-lg bg-code-bg p-3 font-mono text-[11px] leading-relaxed text-code-fg"
      >
        brew tap jnahian/reader.md https://github.com/jnahian/reader.md<br />
        brew install --cask reader-md
      </div>
    </div>
    <div class="hidden w-36 shrink-0 border-l border-border bg-bg-alt px-3.5 py-4 text-muted sm:block">
      <div class="py-0.5 font-semibold text-fg">Getting Started</div>
      <div class="border-l-2 border-accent py-0.5 pl-2.5 text-accent">Install</div>
      <div class="py-0.5 pl-3">Usage</div>
      <div class="py-0.5 pl-3">Shortcuts</div>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Compose in index**

`site/src/pages/index.astro`:

```astro
---
import Base from "../layouts/Base.astro";
import Hero from "../components/Hero.astro";
import AppMock from "../components/AppMock.astro";
---

<Base title="Reader.md — a native markdown reader for macOS">
  <Hero />
  <div class="px-6">
    <AppMock />
  </div>
</Base>
```

- [ ] **Step 4: Verify**

```bash
cd site && npm run build && npm run preview
```

Expected: build passes. `http://localhost:4321/` shows hero (icon, title, two pill buttons, fine print) and the mock app window (traffic lights, sidebar tree with selected README.md and ☁︎ remote root, content pane with brew commands, outline rail with accented "Install"). Check both color schemes; check ~600px width (outline rail hides, layout doesn't overflow).

- [ ] **Step 5: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add site/src
git commit -m "feat(site): hero and CSS app-window mock

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Features + Install sections

**Files:**
- Create: `site/src/components/Features.astro`
- Create: `site/src/components/Install.astro`
- Modify: `site/src/pages/index.astro`

**Interfaces:**
- Produces: `<Features />` (section `id="features"`), `<Install />` (section `id="install"`) — the ids are nav anchor targets from Base.astro.

- [ ] **Step 1: Features**

`site/src/components/Features.astro`:

```astro
---
const features = [
  {
    icon: "📁",
    title: "Open anything",
    body: "Single files, whole folders, or a mix. Add any number of roots, drag folders onto the window, or make it your default markdown app.",
  },
  {
    icon: "☁️",
    title: "Remote SSH folders",
    body: "Browse markdown on a VPS: Reader.md rsyncs it read-only into a local cache using your existing ~/.ssh config. No credentials stored.",
  },
  {
    icon: "⚡️",
    title: "Live reload",
    body: "Edit in your favorite editor — the open file re-renders on save with scroll position preserved, and the file tree stays in sync.",
  },
  {
    icon: "🧜‍♀️",
    title: "Mermaid, LaTeX & code",
    body: "Diagrams, math, and syntax highlighting render out of the box, fully offline. YAML frontmatter shows as a clean table.",
  },
  {
    icon: "🔍",
    title: "Find everything",
    body: "⌘P fuzzy quick-open across all roots, ⇧⌘F live file filter, and a native ⌘F in-page find with match highlighting.",
  },
  {
    icon: "🗺",
    title: "Outline & progress",
    body: "A collapsible outline pane with scrollspy, a reading progress bar, plus word count and reading time in the status bar.",
  },
  {
    icon: "🌗",
    title: "Liquid Glass chrome",
    body: "Native SwiftUI shell with Apple's Liquid Glass on macOS 26 Tahoe (translucent fallback on 13–15). Light, dark, or system — plus Standard, Editorial, and Terminal reading themes.",
  },
  {
    icon: "📄",
    title: "Export to PDF",
    body: "⌘E turns the rendered document into a PDF. Code blocks get copy buttons; images zoom in a click-to-open lightbox.",
  },
  {
    icon: "🔒",
    title: "Private by design",
    body: "All rendering assets are bundled. The only network access is the update check — and the SSH hosts you add yourself.",
  },
];
---

<section id="features" class="bg-bg-alt py-16">
  <div class="mx-auto max-w-5xl px-6">
    <h2 class="mb-12 text-center text-3xl font-bold tracking-tight">
      Built for reading, not editing
    </h2>
    <div class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
      {features.map((f) => (
        <div class="rounded-2xl border border-border bg-card p-6">
          <div class="text-2xl">{f.icon}</div>
          <h3 class="mb-1.5 mt-2.5 text-lg font-semibold">{f.title}</h3>
          <p class="text-sm text-muted">{f.body}</p>
        </div>
      ))}
    </div>
  </div>
</section>
```

- [ ] **Step 2: Install**

`site/src/components/Install.astro`:

```astro
---
const dmg = "https://github.com/jnahian/reader.md/releases/latest/download/Reader.md.dmg";
---

<section id="install" class="py-16">
  <div class="mx-auto max-w-5xl px-6">
    <h2 class="mb-12 text-center text-3xl font-bold tracking-tight">Install in seconds</h2>
    <div class="grid gap-8 md:grid-cols-2">
      <div>
        <h3 class="mb-2 text-xl font-semibold">Homebrew</h3>
        <p class="mb-3 text-sm text-muted">
          Tap once, install, and let the built-in Sparkle updater handle upgrades.
        </p>
        <pre
          class="overflow-x-auto rounded-xl bg-code-bg p-4 font-mono text-sm leading-relaxed text-code-fg"><code>brew tap jnahian/reader.md https://github.com/jnahian/reader.md
brew install --cask reader-md</code></pre>
      </div>
      <div>
        <h3 class="mb-2 text-xl font-semibold">Direct download</h3>
        <p class="mb-3 text-sm text-muted">
          Grab the DMG and drag Reader.md to Applications. First launch:
          right-click → Open (the app is signed but not notarized).
        </p>
        <a
          href={dmg}
          class="inline-block rounded-full bg-accent px-6 py-3 font-medium text-accent-fg hover:opacity-90"
        >Download Reader.md.dmg</a>
      </div>
    </div>
  </div>
</section>
```

- [ ] **Step 3: Compose in index**

In `site/src/pages/index.astro`, add imports and render after `<AppMock />`'s wrapper div:

```astro
---
import Base from "../layouts/Base.astro";
import Hero from "../components/Hero.astro";
import AppMock from "../components/AppMock.astro";
import Features from "../components/Features.astro";
import Install from "../components/Install.astro";
---

<Base title="Reader.md — a native markdown reader for macOS">
  <Hero />
  <div class="px-6">
    <AppMock />
  </div>
  <Features />
  <Install />
</Base>
```

- [ ] **Step 4: Verify**

```bash
cd site && npm run build && npm run preview
```

Expected: 9 feature cards in a responsive grid on the alt background; install section with brew code block and DMG button. Nav links `Features` / `Install` scroll to the sections. Both color schemes look right.

- [ ] **Step 5: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add site/src
git commit -m "feat(site): features grid and install section

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Shortcuts + Contribute sections

**Files:**
- Create: `site/src/components/Shortcuts.astro`
- Create: `site/src/components/Contribute.astro`
- Modify: `site/src/pages/index.astro`

**Interfaces:**
- Produces: `<Shortcuts />`, `<Contribute />` (no props). Shortcut data uses the **v1.6.0 bindings** (⌘F find in page, ⇧⌘F filter files).

- [ ] **Step 1: Shortcuts**

`site/src/components/Shortcuts.astro`:

```astro
---
const keys = [
  { action: "Quick open", keys: "⌘P" },
  { action: "Open file", keys: "⌘O" },
  { action: "Find in page", keys: "⌘F" },
  { action: "Filter files", keys: "⇧⌘F" },
  { action: "Find next / previous", keys: "⌘G / ⇧⌘G" },
  { action: "Back / forward", keys: "⌘[ / ⌘]" },
  { action: "Toggle sidebar", keys: "⌘\\" },
  { action: "Toggle outline", keys: "⇧⌘O" },
  { action: "Text size", keys: "⌘+ / ⌘− / ⌘0" },
  { action: "Export PDF", keys: "⌘E" },
  { action: "Reload", keys: "⌘R" },
  { action: "Shortcuts help", keys: "⌘/" },
];
---

<section class="bg-bg-alt py-16">
  <div class="mx-auto max-w-3xl px-6">
    <h2 class="mb-12 text-center text-3xl font-bold tracking-tight">Keyboard-first</h2>
    <div class="grid gap-x-10 sm:grid-cols-2">
      {keys.map((k) => (
        <div class="flex items-center justify-between border-b border-border py-2.5 text-sm">
          <span class="text-muted">{k.action}</span>
          <kbd class="whitespace-nowrap rounded-md border border-border bg-kbd px-2 py-0.5 font-sans text-xs">{k.keys}</kbd>
        </div>
      ))}
    </div>
    <p class="mt-6 text-center text-sm text-muted">
      <a href="/shortcuts" class="underline hover:text-fg">See the full list →</a>
    </p>
  </div>
</section>
```

- [ ] **Step 2: Contribute**

`site/src/components/Contribute.astro`:

```astro
---
const repo = "https://github.com/jnahian/reader.md";
const links = [
  {
    icon: "⭐️",
    title: "Star the repo",
    body: "Reader.md is free and MIT-licensed. A star helps others find it.",
    href: repo,
    cta: "Star on GitHub",
  },
  {
    icon: "💬",
    title: "Share feedback",
    body: "Found a bug or wish it did something more? Open an issue — every report gets read.",
    href: `${repo}/issues/new`,
    cta: "Report an issue",
  },
  {
    icon: "🛠",
    title: "Contribute",
    body: "PRs welcome — the contributing guide covers setup, conventions, and the PR flow.",
    href: `${repo}/blob/main/CONTRIBUTING.md`,
    cta: "Read the guide",
  },
];
---

<section class="py-16">
  <div class="mx-auto max-w-5xl px-6">
    <h2 class="mb-12 text-center text-3xl font-bold tracking-tight">Open source, open ears</h2>
    <div class="grid gap-5 md:grid-cols-3">
      {links.map((l) => (
        <div class="rounded-2xl border border-border bg-card p-6 text-center">
          <div class="text-2xl">{l.icon}</div>
          <h3 class="mb-1.5 mt-2.5 text-lg font-semibold">{l.title}</h3>
          <p class="mb-4 text-sm text-muted">{l.body}</p>
          <a href={l.href} class="text-sm font-medium text-accent hover:underline">{l.cta} →</a>
        </div>
      ))}
    </div>
  </div>
</section>
```

- [ ] **Step 3: Compose in index (final landing page)**

`site/src/pages/index.astro`:

```astro
---
import Base from "../layouts/Base.astro";
import Hero from "../components/Hero.astro";
import AppMock from "../components/AppMock.astro";
import Features from "../components/Features.astro";
import Install from "../components/Install.astro";
import Shortcuts from "../components/Shortcuts.astro";
import Contribute from "../components/Contribute.astro";
---

<Base title="Reader.md — a native markdown reader for macOS">
  <Hero />
  <div class="px-6">
    <AppMock />
  </div>
  <Features />
  <Install />
  <Shortcuts />
  <Contribute />
</Base>
```

- [ ] **Step 4: Verify**

```bash
cd site && npm run build && npm run preview
```

Expected: full landing page — hero, mock, features, install, shortcut rows with `kbd` chips (⌘F says "Find in page"), contribute cards. Both color schemes.

- [ ] **Step 5: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add site/src
git commit -m "feat(site): shortcuts and contribute sections complete the landing page

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Doc pages — /changelog, /faq, /shortcuts

**Files:**
- Create: `site/src/layouts/DocPage.astro`
- Create: `site/src/pages/changelog.astro`
- Create: `site/src/pages/faq.astro`
- Create: `site/src/pages/shortcuts.astro`

**Interfaces:**
- Consumes: `Base.astro` (Task 3); `src/generated/*.md` (Task 2).
- Produces: three routes rendering the bundled markdown in a prose column.

- [ ] **Step 1: DocPage layout with prose styles**

`site/src/layouts/DocPage.astro`:

```astro
---
import Base from "./Base.astro";

interface Props {
  title: string;
  description?: string;
}

const { title, description } = Astro.props;
---

<Base title={title} description={description}>
  <article class="doc-prose mx-auto max-w-2xl px-6 py-16">
    <slot />
  </article>
</Base>

<style is:global>
  .doc-prose {
    line-height: 1.65;
  }
  .doc-prose h1 {
    font-size: 2.25rem;
    font-weight: 700;
    letter-spacing: -0.01em;
    margin-bottom: 1rem;
  }
  .doc-prose h2 {
    font-size: 1.5rem;
    font-weight: 600;
    margin: 2.5rem 0 0.75rem;
    padding-bottom: 0.375rem;
    border-bottom: 1px solid var(--border);
  }
  .doc-prose h3 {
    font-size: 1.125rem;
    font-weight: 600;
    margin: 1.75rem 0 0.5rem;
  }
  .doc-prose p,
  .doc-prose ul,
  .doc-prose ol {
    margin-bottom: 0.875rem;
    color: var(--fg);
  }
  .doc-prose ul {
    list-style: disc;
    padding-left: 1.5rem;
  }
  .doc-prose ol {
    list-style: decimal;
    padding-left: 1.5rem;
  }
  .doc-prose li {
    margin-bottom: 0.25rem;
  }
  .doc-prose a {
    color: var(--accent);
  }
  .doc-prose a:hover {
    text-decoration: underline;
  }
  .doc-prose code {
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: 0.875em;
    background: var(--kbd);
    border-radius: 0.375rem;
    padding: 0.125rem 0.375rem;
  }
  .doc-prose pre {
    background: var(--code-bg);
    color: var(--code-fg);
    border-radius: 0.75rem;
    padding: 1rem;
    overflow-x: auto;
    margin-bottom: 0.875rem;
  }
  .doc-prose pre code {
    background: none;
    padding: 0;
    font-size: 0.8125rem;
  }
  .doc-prose table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 1.25rem;
    font-size: 0.9375rem;
  }
  .doc-prose th {
    text-align: left;
    font-weight: 600;
    padding: 0.5rem 0.75rem;
    border-bottom: 2px solid var(--border);
  }
  .doc-prose td {
    padding: 0.5rem 0.75rem;
    border-bottom: 1px solid var(--border);
  }
  .doc-prose hr {
    border: 0;
    border-top: 1px solid var(--border);
    margin: 2rem 0;
  }
  .doc-prose strong {
    font-weight: 600;
  }
</style>
```

- [ ] **Step 2: The three pages**

`site/src/pages/changelog.astro`:

```astro
---
import DocPage from "../layouts/DocPage.astro";
import { Content } from "../generated/CHANGELOG.md";
---

<DocPage title="Changelog — Reader.md" description="What's new in each Reader.md release.">
  <Content />
</DocPage>
```

`site/src/pages/faq.astro`:

```astro
---
import DocPage from "../layouts/DocPage.astro";
import { Content } from "../generated/FAQ.md";
---

<DocPage title="FAQ — Reader.md" description="Frequently asked questions about Reader.md.">
  <Content />
</DocPage>
```

`site/src/pages/shortcuts.astro`:

```astro
---
import DocPage from "../layouts/DocPage.astro";
import { Content } from "../generated/SHORTCUTS.md";
---

<DocPage title="Keyboard Shortcuts — Reader.md" description="Every Reader.md keyboard shortcut.">
  <Content />
</DocPage>
```

- [ ] **Step 3: Verify**

```bash
cd site && npm run build && npm run preview
```

Expected: `/changelog` shows versioned sections, `/faq` shows Q&A prose, `/shortcuts` shows styled tables. Nav/footer present, both color schemes readable, tables don't overflow on narrow widths (they're small enough; if one does, wrapping is acceptable — no horizontal page scroll).

- [ ] **Step 4: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add site/src
git commit -m "feat(site): changelog, FAQ, and shortcuts pages from bundled docs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Final verification + deploy notes

**Files:**
- Create: `site/README.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Clean build from scratch**

```bash
cd site
rm -rf dist src/generated
npm run build
```

Expected: build passes; `dist/index.html`, `dist/changelog/index.html`, `dist/faq/index.html`, `dist/shortcuts/index.html` all exist.

- [ ] **Step 2: Gradient check (hard requirement)**

```bash
grep -ri "gradient" src/ && echo "FAIL: gradient in source" || echo "src OK"
grep -rli "linear-gradient\|radial-gradient\|conic-gradient" dist/ && echo "FAIL: gradient in output" || echo "dist OK"
```

Expected: `src OK` and `dist OK` (grep finds nothing).

- [ ] **Step 3: No client JS check**

```bash
ls dist/_astro/*.js 2>/dev/null && echo "FAIL: shipped JS" || echo "no JS OK"
```

Expected: `no JS OK`.

- [ ] **Step 4: Visual pass**

Run `npm run preview` and screenshot all four pages in light and dark (browser emulation of `prefers-color-scheme`). Check: no horizontal scroll at 375px width; hero buttons wrap, feature grid stacks, mock hides its outline rail.

- [ ] **Step 5: Deploy notes**

`site/README.md`:

````markdown
# Reader.md landing site

Astro + Tailwind static site for https://github.com/jnahian/reader.md.

## Develop

```bash
npm install
npm run dev      # copies bundled docs (predev) then serves on :4321
```

`src/generated/` holds build-time copies of the app's bundled
`CHANGELOG.md` / `FAQ.md` / `SHORTCUTS.md` (source of truth:
`../Sources/ReaderMd/Resources/docs/`). Never edit the copies.

## Deploy (Vercel or Netlify)

Import the repo and set:

- **Root directory:** `site`
- **Framework preset:** Astro (auto-detected)
- Build command `npm run build`, output `dist` (preset defaults)

Every push to `main` redeploys.
````

- [ ] **Step 6: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add site/README.md
git commit -m "docs(site): develop and deploy notes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
