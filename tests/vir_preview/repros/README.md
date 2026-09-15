# Callback-free host arguments still traverse the callback registry

Standalone Node reproducer for VIR's host dispatcher. No VBP/FLT imports, Lean
build, browser, Wasm compilation, npm installation, or producer edits required.
Point it at an existing VIR checkout's `web/src`, or a matched SDK's `js` folder:

```sh
node callback-free-host-args.mjs /path/to/lean-vir/web/src
# Optional timing evidence, separate from the deterministic counting run:
node callback-free-host-args.mjs /path/to/sdk/js --bench
```

The example calls a three-argument property setter with existing JS resources
while 56 unrelated callback roots are retained. It imports the actual
`VirHostState`, `ObjectValueRuntime`, and type descriptors. Only the Wasm memory
and small resource/scalar exports are mocked; dispatcher and argument lifting
are unmodified. Callback creation throws if unexpectedly reached.

On pinned VIR `36d26bc2` the setter succeeds, creates no callbacks, but performs
**six registry traversals / 336 entry visits**: a snapshot and scan for each
argument. The counted Set is used only for this deterministic witness. `--bench`
uses ordinary Sets, three warmups and six alternating-order pairs, comparing
zero versus 56 unrelated roots. This is not a browser or widget speedup estimate.
After a fix the traversal counts should fall; the script deliberately reports
counts rather than asserting that the old inefficiency must persist.

Upstream candidate: skip snapshot/scan only for descriptor types proven not to
create callbacks when lifted. Preserve existing handling for function and
composite arguments, and preserve cleanup of callbacks created by earlier
arguments when a later lift, host call, or result conversion fails. No target-name
special cases, new provider API, or VBP-specific behavior are requested.

The full-FLT motivation and measured counts are in
[the callback census report](../../../doc/performance/FLT_HOST_CALLBACK_CENSUS.md).
VIR owns the fix and its lifecycle regressions; VBP will validate a reviewed
successor against the retained full-root workload.
