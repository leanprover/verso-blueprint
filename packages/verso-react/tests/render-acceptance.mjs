import assert from "node:assert/strict";
import { isValidElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";

// Actual React elements, not a shadow VDOM or a replacement host implementation.
export function checkRenderer(render) {
  function paragraphs(node, found = new Map()) {
    if (!isValidElement(node)) return found;
    if (node.type === "p") found.set(renderToStaticMarkup(node), node.key);
    for (const child of [].concat(node.props.children ?? [])) paragraphs(child, found);
    return found;
  }
  const before = paragraphs(render(0));
  const inserted = paragraphs(render(1));
  const moved = paragraphs(render(2));
  for (const text of ["A", "B", "C"]) {
    const keyFor = nodes => [...nodes].find(([html]) => html.endsWith(`>${text}</p>`))?.[1];
    assert.ok(keyFor(before), `missing paragraph ${text}`);
    assert.equal(keyFor(inserted), keyFor(before), `insertion changed ${text}'s key`);
    assert.equal(keyFor(moved), keyFor(before), `reorder changed ${text}'s key`);
  }
  const html = renderToStaticMarkup(render(3));
  for (const fragment of ["<em", "<strong", "<code", "<a ", "<pre", "<ul", "<ol",
    "<dl", "<blockquote", "<aside", 'start="3"', "inline child", "unknown child",
    "notice child", "[inline extension: Test.inline]", "[block extension: Test.unknown]",
    'data-verso-math-mode="inline"', 'data-verso-math-mode="display"']) {
    assert.ok(html.includes(fragment), `missing ${fragment}`);
  }
  assert.ok(html.includes("&lt;script&gt;unsafe()&lt;/script&gt;"));
  assert.ok(!html.includes("<script>") && !html.includes("hidden child"));
  assert.ok(!html.includes("data-bp-") && !html.includes("bp_math"));
  function descendantKeys(node, found = []) {
    if (!isValidElement(node)) return found;
    if (["em", "strong", "code", "a", "li", "dt", "dd"].includes(node.type))
      found.push([node.type, node.key]);
    for (const child of [].concat(node.props.children ?? [])) descendantKeys(child, found);
    return found;
  }
  const originalKeys = descendantKeys(render(3));
  assert.ok(originalKeys.length >= 10, "missing nested key fixtures");
  assert.deepEqual(descendantKeys(render(5)), originalKeys,
    "moving a retained parent must not change inline/list descendant keys");
  const grouped = paragraphs(render(4));
  assert.equal(grouped.size, 4);
  for (const [html] of grouped) {
    assert.equal(html.includes('data-verso-focus="cursor"'), !html.endsWith(">unrelated</p>"),
      "fragment focus must reach all visible children, not unrelated siblings");
  }
  return { ordinaryMarkup: true, escapedCode: true, visibleFallbacks: true,
    extensionCallbacks: true, hiddenContentOmitted: true, stableReactKeys: true,
    concatenationFocus: true, siblingLocalDescendantKeys: true };
}
