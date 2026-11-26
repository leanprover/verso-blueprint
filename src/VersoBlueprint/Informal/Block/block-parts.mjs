// The parts of one Blueprint node (its statement, its proof and its Lean code)
// render as separate blocks. When they sit together on the page, each directly
// after the last and all carrying the same `data-bp-owner`, they are joined into
// one card: the earlier part continues into the next. Parts placed elsewhere, or
// after another node's block, stay cards of their own. CSS cannot compare two
// elements' labels, so the page marks the joins.

const partSelector = ".bp_wrapper[data-bp-owner]";

export function joinBlockParts(root) {
  const scope = root instanceof Element || root instanceof Document ? root : document;
  scope.querySelectorAll(partSelector).forEach(function (part) {
    const previous = part.previousElementSibling;
    if (!(previous instanceof Element) || !previous.matches(partSelector)) return;
    if (previous.getAttribute("data-bp-owner") !== part.getAttribute("data-bp-owner")) return;
    previous.classList.add("bp_part_continues");
    part.classList.add("bp_part_joined");
  });
}

export function startBlockParts() {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () { joinBlockParts(document); });
  } else {
    joinBlockParts(document);
  }
}

export default { joinBlockParts, startBlockParts };
