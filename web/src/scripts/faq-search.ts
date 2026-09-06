// Filters /docs/faq. Thirty-one questions: a filter, not a search index, so
// matching is a plain substring over the question and its answer — the same
// shape as the /docs hub's field.
//
// Searching the answers is the point. A collapsed <details> is invisible to
// Safari's find-in-page, so without this the only way to find "rsync" or
// "arm64" would be to open all nine sections by hand.
import { setOpenImmediate } from "./accordion";

export function initFaqSearch() {
  const input = document.querySelector<HTMLInputElement>("#faqsearch");
  if (!input) return;

  const groups = [...document.querySelectorAll<HTMLElement>(".faq-group")];
  const empty = document.querySelector<HTMLElement>("[data-faq-empty]");
  // What was open before filtering started, so clearing the field puts the
  // reader back where they were rather than collapsing their place away.
  let restore: HTMLDetailsElement[] | null = null;

  input.addEventListener("input", () => {
    const q = input.value.trim().toLowerCase();

    if (q && !restore) {
      restore = [...document.querySelectorAll<HTMLDetailsElement>(".faq-q")].filter(
        (d) => d.open
      );
    }

    let hits = 0;
    for (const group of groups) {
      const questions = [...group.querySelectorAll<HTMLDetailsElement>(".faq-q")];

      // A section with no questions is matched on its own prose instead.
      if (!questions.length) {
        const match = !q || (group.dataset.search ?? "").includes(q);
        group.hidden = !match;
        if (match) hits++;
        continue;
      }

      let shown = 0;
      for (const item of questions) {
        const match = !q || (item.dataset.search ?? "").includes(q);
        item.hidden = !match;
        // An answer can match on text the closed row doesn't show, so open a
        // hit to say why it matched.
        if (q) setOpenImmediate(item, match);
        shown += match ? 1 : 0;
      }
      group.hidden = shown === 0;
      hits += shown;
    }

    if (!q && restore) {
      for (const item of document.querySelectorAll<HTMLDetailsElement>(".faq-q"))
        setOpenImmediate(item, restore.includes(item));
      restore = null;
    }

    if (empty) empty.hidden = hits > 0;
  });
}
