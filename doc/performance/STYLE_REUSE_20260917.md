# Component-owned renderer styles

The renderer now creates its 15 ordinary Verso styles and eight Blueprint
extension styles once per content-component factory. Render callbacks capture
the resulting objects, treat them as read-only, and allocate fresh node props
for keys, paths, focus/change markers and extension attributes. No global cache,
new hook, transport layer or cross-update subtree reuse is introduced. Colors
remain CSS variables, so theme changes do not require recreating the component.

`VersoReact.Renderer.render` and `renderMath` now take an explicit `Styles`
argument. Blueprint rendering takes its corresponding styles record. Stateless
test exports create styles per invocation; the retained production component
creates them outside its render callback. The README and all renderer callers
are updated together.

## Retained full-FLT replay

The experimental axis is renderer IR, against baseline VBP `067eb9a8`.
The old package set and every member were copied before rebuilding to
`_out/upstream-vir-20260917/styles-baseline-ir/`. Both variants use the unchanged
direct typed converter, scratch/intern settings, SDK, options and captured input
described in [the rendering-focus report](RENDER_FOCUS_20260917.md).
Lean is 4.34.0-rc2; VIR is `92d7cc91`; Verso is `52c8c955` with the existing
list-widget parser patch. No live demo or FIR package pin is changed.

The existing Chromium replay runs two warmup updates and eight measured updates
per fresh retained session, after initial mount and a control-state change.
Debug and highlighting are off. Each update changes the captured FLT text marker
and version. The boundary includes browser parse/direct conversion, identity
preparation, element construction and React commit up to DOM observation; it
excludes RPC/LSP, server work, package loading, initial mount, paint and waiting
for passive effects. Phase medians must not be added into a total median.

| Run order | Variant | Decode median | Render-to-DOM median | Total median |
| --- | --- | ---: | ---: | ---: |
| 1: `styles-c01` | Shared styles | 80.1 ms | 1,217.0 ms | 1,297.1 ms |
| 2: `styles-b02` | Before | 72.8 ms | 1,284.6 ms | 1,387.3 ms |
| 3: `styles-b03` | Before | 63.5 ms | 1,259.1 ms | 1,319.4 ms |
| 4: `styles-c02` | Shared styles | 68.4 ms | 1,233.2 ms | 1,303.5 ms |
| Pooled, 16 updates | Before | 66.6 ms | 1,259.1 ms | 1,319.4 ms |
| Pooled, 16 updates | Shared styles | 75.0 ms | 1,222.3 ms | 1,297.1 ms |

The two adjacent comparison pairs favor shared styles by 5.3% and 2.1% in
render-to-DOM; the pooled difference is 2.9% (36.8 ms). This is a small,
provisional gain, not a strong precise speedup claim. The original `styles-b01`
screening run overlapped dependency preparation and is excluded from this table.
No builds or profiling ran during the included measured updates.

All four included runs preserve 7,011 elements, checkbox state/identity and an
unchanged paragraph node, with no browser warnings. Normalized DOM hash:
`7e4b7a6d6d590b907523c1246f80b914a9a6b4449222cda7086a85467df57145`.
Text hash:
`ae733007b2d233a50c10e0d95a360f80dab036e852b38bb87e609fbf100e9ad5`.
The harness also runs untimed codec/equivalence and malformed-input controls.

Raw commands, timestamps, package-member hashes, source/bundle/input hashes and
results are retained in each named capture under `_out/upstream-vir-20260917/`.
Baseline replay loads frozen old IR even though the harness source is the current
checkout; its `DecodeProbe.lean` source hash must not be mistaken for the old
package's source identity. Six package-member hashes differ: the three edited
renderer/content owners, the two probe owners and `Vir.Js.Generated`. The latter
has the same source, manifest, declaration count and byte length; capture orders
the `Object.get`/undefined/bool extern declarations before `Array.push` instead
of after it. The other 64 members are byte-identical. Renderer/content member
sizes grow by 7,536 bytes in total.

## Validation scope

The independent generic renderer facet also builds (28 package members, 820
declarations). The existing real-React SSR campaign passes generic constructor,
extension and identity acceptance plus Blueprint math/prelude, informal bodies,
all external-markup display modes, escaped source, malformed fallbacks and session
metadata. Report: `styles-rich-ssr/renderer-acceptance.json`. The full-FLT retained
Chromium acceptance above is separate from SSR and includes no native-math claim.

Lean Beam checks the generic renderer and content component without diagnostics.
Initial dependency setup without restoration hit an existing missing-olean path
failure, before VBP source checking. Restarting with scoped
`LAKE_RESTORE_ARTIFACTS=true` resolved setup; the normal wrapper policy is unchanged.
Targeted batch builds of the direct-codec and Blueprint renderer IR facets pass.
This is targeted dependency-cone evidence, not a clean whole-repository build.

The earlier frozen FIR request remains authoritative and unchanged. This renderer
candidate is not in that snapshot and has not been silently adopted into FIR.

## Separate post-change profile

`styles-profile-01` samples two updates after two warmups, with the same coarse
decode/render windows. Calibration uncertainty is 0.596 ms; all 5,308 Wasm frame
nodes resolve using the unchanged matching release/named artifact evidence.
The 2,173 render-window samples cover 2,288.9 ms by interval weighting.

| Disjoint sampled self bucket | Previous profile | Shared-styles profile |
| --- | ---: | ---: |
| Interpreter dispatch/evaluation | 38.5% | 46.0% |
| Symbol/constant/name lookup | 14.1% | 11.5% |
| JavaScript/browser | 27.3% | 21.1% |
| Other Wasm | 13.5% | 13.8% |
| Allocation/refcount/vector storage | 6.7% | 7.6% |

Inclusive host-boundary coverage decreases from 23.2% to 17.0%; inclusive
`commitRoot` coverage remains about 0.65%. These overlap the self buckets, and
the profiles have different sampled totals. This supports reduced boundary work,
but neither isolates styles nor supplies an independent precise speedup.
The remaining dominant caller is still the interpreted Lean content callback
under React `renderWithHooks`, at 96.8% inclusive coverage. Do not mistake that
for React's own processing cost. Decoder optimization remains paused.

Keep the candidate as a small allocation/boundary simplification, with the
provisional timing result above. Further rendering work should target the
remaining interpreted node/attribute construction on the shared source, with
separate matched FIR qualification; this experiment makes no FIR speedup claim.
