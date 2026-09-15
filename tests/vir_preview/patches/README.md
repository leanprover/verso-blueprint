# Local Verso list source-range repair

`verso-list-source-ranges.patch` applies to Verso
`52c8c9557bcb5cc8c0edc0ee37e74311a3d53ee9`.
It gives unordered/ordered list delimiters source information, following the
existing paragraph/definition-list parser. Without it, Lean's canonical snapshot
lookup cannot find the lists and `Lean.Widget.getWidgets` returns no panel.
Both list markers and bodies, including nested lists, are covered by the live
RPC acceptance test. No document rendering or widget-discovery API is replaced.

This patch is applied locally to the VBP demo and FLT's independent Verso
dependency. It is not an upstream commit or a changed dependency pin. On a fresh
consumer, review and apply it in that consumer's `.lake/packages/verso`:

```sh
git apply --check /absolute/path/to/verso-list-source-ranges.patch
git apply /absolute/path/to/verso-list-source-ranges.patch
```

Then rebuild normally; do not edit cached oleans or force owner-module mtimes.
Already patched copies can be checked with `git apply --reverse --check`.
Retire this patch after adopting a Verso revision with the source-range repair.
