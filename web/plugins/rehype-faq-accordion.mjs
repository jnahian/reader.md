// docs/faq.md is written as plain markdown — `## section`, then `### question`
// with the answer under it — so it stays readable in Reader.md and on GitHub.
// The site renders it as an accordion, which needs a wrapper markdown can't
// express, so the grouping happens here instead of in the source:
//
//   <section class="faq-group">        one per ## heading
//     <h2>…</h2>
//     <div class="qa-list" data-faq>   only if the section has questions
//       <details class="faq-q">        one per ### heading
//         <summary><h3 id="…">…</h3></summary>
//         <div class="faq-q__a">…</div>
//       </details>
//
// The h3 keeps its id, so /docs/faq#is-it-sandboxed still addresses a question;
// the client script opens the <details> around a targeted one.
import { visit } from "unist-util-visit";

const el = (tagName, properties, children) => ({
  type: "element",
  tagName,
  properties,
  children,
});

const isTag = (node, tag) => node.type === "element" && node.tagName === tag;

// Splits a flat list of siblings on `tag`, keeping anything before the first
// match as a leading remainder.
function sections(children, tag) {
  const lead = [];
  const groups = [];
  for (const node of children) {
    if (isTag(node, tag)) groups.push([node]);
    else if (groups.length) groups[groups.length - 1].push(node);
    else lead.push(node);
  }
  return { lead, groups };
}

export function rehypeFaqAccordion() {
  return (tree, file) => {
    if (!/(^|\/)docs\/faq\.md$/.test(file?.path?.replace(/\\/g, "/") ?? "")) return;

    visit(tree, "root", (root) => {
      const { lead, groups } = sections(root.children, "h2");

      root.children = [
        ...lead,
        ...groups.map(([heading, ...body]) => {
          const { lead: prose, groups: questions } = sections(body, "h3");

          const list = questions.map(([q, ...answer]) =>
            el("details", { className: ["faq-q"] }, [
              el("summary", { className: ["faq-q__q"] }, [q]),
              el("div", { className: ["faq-q__a"] }, answer),
            ])
          );

          return el("section", { className: ["faq-group"] }, [
            heading,
            ...prose,
            // A section of plain prose ("Something's wrong") has no questions;
            // emitting the list anyway would draw an empty bordered box.
            ...(list.length
              ? [el("div", { className: ["qa-list"], "data-faq": "" }, list)]
              : []),
          ]);
        }),
      ];
    });
  };
}
