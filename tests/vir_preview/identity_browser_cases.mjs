/* Behavioral observations, not timing instrumentation. No custom React reconciler. */
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";

export function identityBrowserCases(render, policy, reset = () => {}) {
  const check = (value, message) => { if (!value) throw Error(message); };
  check(["content", "position", "content-path", "content-local"].includes(policy), "unknown identity policy");
  const positional = policy === "position";
  const localKeys = policy === "content-local";
  const container = document.getElementById("app");
  const cases = [
    { name: "paragraph-edit", before: 0, after: 1, from: "p", index: 1,
      to: "p", toIndex: 1, retained: positional },
    { name: "paragraph-insert", before: 0, after: 2, from: "p", index: 1,
      to: "p", toIndex: 2, retained: !positional },
    { name: "paragraph-reorder", before: 0, after: 3, from: "p", index: 1,
      to: "p", toIndex: 2, retained: !positional },
    { name: "labeled-edit", before: 4, after: 5, label: "A", retained: true },
    { name: "labeled-insert", before: 4, after: 6, label: "A", retained: true },
    { name: "labeled-reorder", before: 4, after: 7, label: "A", retained: true },
    { name: "unlabeled-edit", before: 8, after: 11, label: "A", retained: positional },
    { name: "unlabeled-insert", before: 8, after: 9, label: "A", retained: !positional,
      transferredTo: positional ? "X" : null },
    { name: "unlabeled-delete", before: 8, after: 10, label: "A", removed: true,
      transferredTo: positional ? "B" : null },
    { name: "duplicate-insert-ambiguous", before: 12, after: 13, label: "same", retained: true },
    { name: "section-title-edit", before: 14, after: 15, label: "nested", retained: positional },
    { name: "container-child-edit", before: 16, after: 17, label: "nested", retained: positional },
  ];
  if (policy === "content-path" || localKeys) cases.push(
    ...[".vir-verso-footnote", ".vir-verso-math", "em", "strong", ".identity-inline-extension",
      "code.vir-verso-extension-unsupported"].map(selector => ({
        name: `parent-move:${selector}`, before: 18, after: 19, from: selector,
        retained: localKeys, parentMove: true,
        trackOpen: selector.includes("footnote") || selector.includes("inline-extension"),
      })),
    ...["unordered", "ordered", "description"].map(label => ({
      name: `list-parent-move:${label}`, before: 18, after: 19, label, retained: localKeys, parentMove: true,
    })),
  );
  const warnings = [];
  const originalError = console.error;
  console.error = (...args) => { warnings.push(args.map(String).join(" ")); originalError(...args); };
  const rows = [];
  try {
    for (const test of cases) {
      reset();
      const root = createRoot(container);
      try {
        flushSync(() => root.render(render(test.before)));
        const selector = test.label ? `details[data-test-label="${test.label}"]` : test.from;
        const original = container.querySelectorAll(selector)[test.index ?? 0];
        check(original, `${test.name}: missing initial node`);
        const oldChild = original.querySelector("p");
        const oldNavigation = original.closest("[data-verso-block]")?.dataset.versoBlock;
        if (test.label || test.trackOpen) original.open = true;
        const selection = window.getSelection();
        selection.removeAllRanges();
        if (!test.label) {
          const range = document.createRange();
          range.selectNodeContents(original);
          selection.addRange(range);
        }
        flushSync(() => root.render(render(test.after)));
        const current = container.querySelectorAll(test.to ?? selector)[test.toIndex ?? test.index ?? 0];
        const retained = original === current;
        const newNavigation = current?.closest("[data-verso-block]")?.dataset.versoBlock;
        if (test.parentMove) check(oldNavigation && newNavigation && oldNavigation !== newNavigation,
          `${test.name}: navigation path did not follow the moved block`);
        const openLabels = [...container.querySelectorAll("details")]
          .filter(node => node.open && node.dataset.testLabel).map(node => node.dataset.testLabel);
        if (!test.removed) check(retained === test.retained, `${test.name}: unexpected retention`);
        if (test.trackOpen) check(current.open === test.retained, `${test.name}: open state lost`);
        if (test.label) {
          const expected = test.transferredTo ? [test.transferredTo] :
            !test.removed && test.retained ? [test.label] : [];
          check(JSON.stringify(openLabels) === JSON.stringify(expected), `${test.name}: unexpected state ownership`);
        }
        rows.push({ name: test.name, retained, oldNodeConnected: original.isConnected,
          childRetained: oldChild ? current?.querySelector("p") === oldChild : null,
          oldNavigation, newNavigation,
          openLabels, selectionAfter: selection.toString(), textAfter: container.textContent });
        selection.removeAllRanges();
      } finally { flushSync(() => root.unmount()); }
    }
    check(warnings.length === 0, `React warnings: ${warnings.join("; ")}`);
    return { policy, rows, warnings, duplicateCaveat: "Identical unlabelled siblings cannot identify which occurrence was inserted." };
  } finally { console.error = originalError; }
}
