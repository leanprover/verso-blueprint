/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public meta import VersoBlueprintVir.Preview.Model
public meta import Verso.Doc.Name
public meta import Lean.Server.Rpc.RequestHandling

public section

namespace VersoBlueprint.Experimental.VirPreview.Server

open Lean Server

private meta unsafe def evalManualPartUnsafe (env : Environment) (options : Options)
    (name : Name) : Except String (Verso.Doc.Part Verso.Genre.Manual) := do
  let some declaration := env.find? name
    | throw s!"Unknown Verso document constant `{name}`"
  -- Check the complete type, including the genre, before unsafe evaluation.
  let expected := mkApp (mkConst ``Verso.Doc.VersoDoc) (mkConst ``Verso.Genre.Manual)
  unless declaration.type == expected do
    throw "The current document does not use the Manual genre"
  -- The open document is runtime code, not a meta declaration. Its complete
  -- type was checked above; evaluation intentionally crosses that staging boundary.
  let document ← env.evalConst (Verso.Doc.VersoDoc Verso.Genre.Manual) options name (checkMeta := false)
  pure document.toPart

@[implemented_by evalManualPartUnsafe]
private meta opaque evalManualPart (env : Environment) (options : Options)
    (name : Name) : Except String (Verso.Doc.Part Verso.Genre.Manual)

/-- Preview the open module's complete Manual document from its server snapshot.
This retains the existing full-document evaluation boundary: it waits for the
end snapshot and checked environment, not just the block under the cursor.
No separate build, traversal, timing instrumentation, or document cache is added. -/
@[server_rpc_method]
meta def previewDocument (pos : Lsp.Position) : RequestM (RequestTask String) := do
  let editorDocument ← RequestM.readDoc
  RequestM.bindWaitFindSnap editorDocument (·.isAtEnd)
    (notFoundX := throw ⟨.invalidParams, "The Blueprint document is still elaborating"⟩)
    (x := fun snap => do
      let checked : ServerTask Kernel.Environment := snap.env.checked
      RequestM.mapTaskCostly checked fun _ => do
        RequestM.checkCancelled
        let name := Verso.Doc.docName editorDocument.meta.mod
        if !(snap.env.contains name) then
          return (Preview.unavailable "This module has no Verso document").encode
        let part ← match evalManualPart snap.env snap.cmdState.scopes.head!.opts name with
          | .ok part => pure part
          | .error message => throw ⟨.internalError, s!"Could not evaluate the Blueprint: {message}"⟩
        RequestM.checkCancelled
        let cursorToken := s!"{pos.line}:{pos.character}"
        return (Preview.ready {
          version := editorDocument.meta.version
          correlationId := s!"{editorDocument.meta.version}:{cursorToken}"
          cursorToken
          document := part
        }).encode)

end VersoBlueprint.Experimental.VirPreview.Server
