import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

-- A real rendered occurrence with an intentionally blank preview body. This
-- distinguishes resource availability from accepted node/relationship semantics.
open Verso Doc Elab Genre Manual in
block_extension Block.blankPreviewResource where
  data := Lean.Json.null
  traverse _ _ _ := pure none
  toHtml := some fun _ _ _ _ _ => pure .empty
  toTeX := some fun _ _ _ _ _ => pure .empty

open Verso Doc Elab in
@[block_command]
public meta def blank_preview_resource : BlockCommandOf Unit
  | () => ``(Block.other Block.blankPreviewResource #[])

#doc (Manual) "Preview Relationships" =>

:::definition "used_target" (lean := "Nat.add")
Target statement with associated Lean code.
:::

:::definition "used_aux_target"
Auxiliary target statement for multi-use proof previews.
:::

:::group "preview_relation_group"
Preview relation group.
:::

:::lemma_ "used_statement"
Statement depends on {uses "used_target" (origin := "automatic") (intent := "technical")}[].
:::

:::theorem "used_proof"
Statement facet marker for preview relationships.
:::

:::proof "used_proof"
Proof facet marker for preview relationships, depending on {uses "used_target" (intent := "auxiliary")}[].
:::

:::theorem "used_proof_panel"
Statement facet for a proof with multiple dependencies.
:::

:::proof "used_proof_panel" (uses := "used_target")
Proof panel marker for preview relationships, also depending on {uses "used_aux_target"}[].
:::

:::theorem "used_grouped_proof_panel" (parent := "preview_relation_group") (lean := "Nat.add")
Grouped statement facet with group, used-by, and Lean metadata.
:::

:::proof "used_grouped_proof_panel" (uses := "used_target")
Grouped proof panel marker for preview relationships, also depending on {uses "used_aux_target"}[].
:::

:::lemma_ "used_grouped_consumer" (parent := "preview_relation_group") (uses := "used_grouped_proof_panel")
Consumer statement that makes the grouped statement used-by and group chips non-empty.
:::

:::theorem "preview_facets"
Statement facet marker for preview relationships.
:::

:::proof "preview_facets"
Proof facet marker for preview relationships.
:::

:::group "prepared_resource_group"
Prepared resource group.
:::

:::definition "prepared_resource_target" (parent := "prepared_resource_group")
Available prepared resource body.

This cached body retains {bpref "prepared_resource_blank"}[cached blank reference]
and {uses "prepared_resource_single"}[cached available reference].
:::

:::theorem "prepared_resource_blank" (uses := "prepared_resource_target") (parent := "prepared_resource_group")
{blank_preview_resource}
:::

:::lemma_ "prepared_resource_single"
This single dependency retains its link: {uses "prepared_resource_blank" (intent := "technical")}[blank target].
:::

:::lemma_ "prepared_resource_multiple" (uses := "prepared_resource_blank")
A second dependency has a body: {uses "prepared_resource_target"}[available target].
:::

Explicit references retain their presentation: {bpref "prepared_resource_blank"}[blank reference]
and {bpref "prepared_resource_target"}[available reference].
