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
//
// Each question also carries the lowercased text of its question and answer as
// data-search, so the field above the page filters without walking 31 rows of
// DOM on every keystroke. A section with no questions ("Something's wrong")
// carries its own instead, so it is filtered as one unit rather than being
// stranded on screen with nothing under it.
import { visit } from "unist-util-visit";

const el = (tagName, properties, children) => ({
  type: "element",
  tagName,
  properties,
  children,
});

const isTag = (node, tag) => node.type === "element" && node.tagName === tag;

// Recurses through <code>, <strong>, <a> and friends, so "arm64" inside a code
// span is findable.
function text(node) {
  if (node.type === "text") return node.value;
  return (node.children ?? []).map(text).join("");
}

const flatten = (nodes) =>
  nodes.map(text).join(" ").replace(/\s+/g, " ").trim();

const searchable = (nodes) => flatten(nodes).toLowerCase();

// The field, the live count, and the empty state. Emitted here rather than in
// the page component so everything that knows the FAQ is special stays in this
// file.
const searchField = () =>
  el("div", { className: ["faq-search"] }, [
    el("div", { className: ["filter"] }, [
      {
        type: "element",
        tagName: "svg",
        properties: {
          className: ["filter__icon"],
          viewBox: "0 0 24 24",
          width: "17",
          height: "17",
          fill: "none",
          stroke: "currentColor",
          strokeWidth: "2",
          strokeLinecap: "round",
          ariaHidden: "true",
        },
        children: [
          el("circle", { cx: "11", cy: "11", r: "7" }, []),
          el("path", { d: "M20 20l-3.5-3.5" }, []),
        ],
      },
      el("input", {
        id: "faqsearch",
        className: ["filter__input"],
        type: "search",
        autoComplete: "off",
        placeholder: "Search the questions…",
        ariaLabel: "Search the FAQ",
      }, []),
    ]),
    el("p", { className: ["faq-search__empty"], dataFaqEmpty: "", hidden: true }, [
      { type: "text", value: "No question matches that. " },
      el("a", { href: "https://github.com/jnahian/reader.md/issues" }, [
        { type: "text", value: "Ask on the issue tracker" },
      ]),
      { type: "text", value: ", or read the app's own help — Help → FAQ." },
    ]),
  ]);

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

    // The same questions, as plain text, for the page's FAQPage JSON-LD. Read
    // off the tree here because this is where the answer's extent is already
    // known — a second parse in the page would have to re-derive it.
    const questionsAndAnswers = [];

    visit(tree, "root", (root) => {
      const { lead, groups } = sections(root.children, "h2");

      root.children = [
        ...lead,
        searchField(),
        ...groups.map(([heading, ...body]) => {
          const { lead: prose, groups: questions } = sections(body, "h3");

          const list = questions.map(([q, ...answer]) => {
            questionsAndAnswers.push({ q: flatten([q]), a: flatten(answer) });
            return el("details", {
              className: ["faq-q"],
              dataSearch: searchable([q, ...answer]),
            }, [
              el("summary", { className: ["faq-q__q"] }, [q]),
              el("div", { className: ["faq-q__a"] }, answer),
            ]);
          });

          return el("section", {
            className: ["faq-group"],
            // Only a section with no questions of its own needs this; the rest
            // are filtered by the questions inside them.
            ...(questions.length ? {} : { dataSearch: searchable(prose) }),
          }, [
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

    // Reaches the page as render()'s remarkPluginFrontmatter, which is outside
    // the collection schema — so this doesn't have to be declared as content.
    const frontmatter = file?.data?.astro?.frontmatter;
    if (frontmatter) frontmatter.faq = questionsAndAnswers;
  };
}
