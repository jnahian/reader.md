// Hands the reader the markdown the page was rendered from — the thing you
// actually want in an LLM prompt, rather than the page's HTML scraped back into
// prose. The text is fetched from the page's own .md twin
// (pages/docs/[slug].md.ts) so the HTML doesn't carry a second copy of it.
const RESET = 2000;

export function initCopyMarkdown() {
  const button = document.querySelector<HTMLButtonElement>("[data-copy-md]");
  const url = button?.dataset.copyMd;
  if (!button || !url) return;

  const label = button.querySelector<HTMLElement>("[data-copy-md-label]");
  let timer = 0;

  button.addEventListener("click", async () => {
    try {
      const res = await fetch(url);
      // A failed fetch or a blocked clipboard leaves the button alone: saying
      // "Copied" over an empty clipboard is worse than appearing to do nothing.
      if (!res.ok) return;
      await navigator.clipboard.writeText(await res.text());
    } catch {
      return;
    }

    button.classList.add("is-copied");
    if (label) label.textContent = "Copied";
    clearTimeout(timer);
    timer = window.setTimeout(() => {
      button.classList.remove("is-copied");
      if (label) label.textContent = "Copy markdown";
    }, RESET);
  });
}
