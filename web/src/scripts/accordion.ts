// <details> has no height to transition between — the browser goes from
// display:none to laid out — so the slide is animated here. Without this module
// an accordion still opens and closes, just instantly.
//
// Used by the landing section (exclusive: one answer at a time) and the FAQ
// docs page (independent: 31 questions across nine sections, where closing a
// far-away one on every click would be noise).
const DURATION = 280;
const EASING = "cubic-bezier(.4,0,.2,1)";

const reduced = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const running = new WeakMap<HTMLDetailsElement, Animation>();

export function slide(item: HTMLDetailsElement, open: boolean) {
  const panel = item.lastElementChild as HTMLElement | null;
  if (!panel) return;
  running.get(item)?.cancel();

  if (reduced()) {
    item.open = open;
    delete item.dataset.closing;
    return;
  }

  // Opening has to happen first: a closed <details> has no laid-out panel to
  // measure.
  if (open) item.open = true;
  const full = `${panel.scrollHeight}px`;

  const animation = panel.animate(
    [
      { height: open ? "0px" : full, opacity: open ? 0 : 1 },
      { height: open ? full : "0px", opacity: open ? 1 : 0 },
    ],
    { duration: DURATION, easing: EASING }
  );
  running.set(item, animation);
  if (open) delete item.dataset.closing;
  else item.dataset.closing = "1";

  animation.finished
    .then(() => {
      if (!open) item.open = false;
      delete item.dataset.closing;
      running.delete(item);
    })
    .catch(() => {}); // cancelled by a newer click
}

export function initAccordion(list: Element, { exclusive = false } = {}) {
  const items = [...list.querySelectorAll("details")];

  // Exclusivity moves from the browser to the handler below: animating a
  // sibling closed needs it to stay open until its animation ends, which a
  // named group forbids.
  items.forEach((item) => item.removeAttribute("name"));

  items.forEach((item) => {
    item.querySelector("summary")?.addEventListener("click", (event) => {
      event.preventDefault();
      // Mid-close the element is still `open`, so ask the flag instead.
      const open = !item.open || item.dataset.closing === "1";
      if (open && exclusive) {
        items.forEach((other) => {
          if (other !== item && other.open && other.dataset.closing !== "1")
            slide(other, false);
        });
      }
      slide(item, open);
    });
  });
}

// A shared link lands on a question that is closed, and a closed <details>
// has no box to scroll to — so open it, then scroll on the next frame.
export function revealHash() {
  const id = location.hash.slice(1);
  if (!id) return;
  const target = document.getElementById(decodeURIComponent(id));
  const item = target?.closest("details");
  if (!item) return;
  item.open = true;
  requestAnimationFrame(() => target!.scrollIntoView({ block: "start" }));
}
