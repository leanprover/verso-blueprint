/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoManual

namespace Verso.VersoBlueprintTests.StorageSchemaCompat

open Lean
open Informal
open Verso.Genre Manual

private def legacyProvenanceJson : Json :=
  Json.mkObj [
    ("inWorkspace", Json.mkObj [
      ("moduleName", toJson `Legacy.Module),
      ("sourcePath", toJson "Legacy/Module.lean")
    ])
  ]

/-- info: true -/
#guard_msgs in
#eval
  match fromJson? (α := Data.ExternalDeclProvenance) legacyProvenanceJson,
      fromJson? (α := Data.ExternalDeclProvenance) (.str "unknown") with
  | .ok (.inWorkspace moduleName sourcePath), .ok .unknown =>
      moduleName == `Legacy.Module && sourcePath == "Legacy/Module.lean"
  | _, _ => false

private def legacyExternalRenderJson (decl : Name) : Json :=
  Json.mkObj [("error", toJson (DocGenRenderError.moduleUnavailable decl))]

private def legacyExternalRefJson (decl : Name) : Json :=
  Json.mkObj [
    ("written", toJson decl),
    ("canonical", toJson decl),
    ("origin", .str "directiveLean"),
    ("present", toJson true),
    ("provedStatus", toJson Data.ProvedStatus.proved),
    ("provenance", .str "unknown"),
    ("range?", toJson (none : Option DeclarationRange)),
    ("selectionRange?", toJson (none : Option DeclarationRange)),
    ("kind", toJson Data.NodeKind.definition),
    ("sourceHref?", toJson (none : Option String)),
    ("render", legacyExternalRenderJson decl)
  ]

private def legacyBlockDataJson (label : Name) : Json :=
  Json.mkObj [
    ("kind", toJson (Data.InProgressKind.statement .definition)),
    ("codeData", Json.mkObj [
      ("external", Json.mkObj [
        ("decls", .arr #[legacyExternalRefJson `Nat.add])
      ])
    ]),
    ("label", toJson label),
    ("parent", toJson (none : Option Data.Parent)),
    ("count", toJson 3),
    ("numberingMode", toJson NumberingMode.sub),
    ("partPrefix", toJson (some "7")),
    ("globalCount", toJson (none : Option Nat)),
    ("statementDeps", toJson (#[] : Array Data.Label)),
    ("proofDeps", toJson (#[] : Array Data.Label)),
    ("owner", toJson (none : Option Data.AuthorId)),
    ("ownerDisplayName", toJson (none : Option String)),
    ("ownerUrl", toJson (none : Option String)),
    ("ownerImageUrl", toJson (none : Option String)),
    ("tags", toJson (#[] : Array String)),
    ("effort", toJson (none : Option String)),
    ("priority", toJson (none : Option String)),
    ("prUrl", toJson (none : Option String))
  ]

/-- info: true -/
#guard_msgs in
#eval
  let label := `bp.storage.legacy
  let json := legacyBlockDataJson label
  let parsedHasExternalCode :=
    match fromJson? (α := BlockData) json with
    | .ok { codeData := some (.external decls), .. } =>
        decls.size == 1 && decls[0]!.canonical == `Nat.add
    | _ => false
  let state :=
    Informal.TraversalIndex.Nodes.saveData
      (TraverseState.initialize default)
      label
      json
  match Informal.TraversalIndex.Nodes.storedData? state label,
      Informal.TraversalIndex.Nodes.data? state label with
  | some stored, some recovered =>
      parsedHasExternalCode &&
      stored.label == label &&
      stored.partPrefix == some "7" &&
      recovered.codeData.isNone &&
      recovered.displayNumber state == "7.3"
  | _, _ => false

private def legacyGroupJson : Json :=
  Json.mkObj [("label", toJson `bp.group.legacy), ("header", toJson "Legacy group")]

/-- info: true -/
#guard_msgs in
#eval
  match fromJson? (α := GroupBlockData) legacyGroupJson with
  | .ok group => group.label == `bp.group.legacy && group.header == "Legacy group"
  | .error _ => false

end Verso.VersoBlueprintTests.StorageSchemaCompat
