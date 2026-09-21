/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public meta import VersoBlueprintVir.Preview.Model
public meta import VersoBlueprintVir.Preview.Source
public meta import Verso.Doc.Name
public meta import Lean.Server.Rpc.RequestHandling

public section

namespace VersoBlueprint.Experimental.VirPreview.Server

open Lean Server

private meta initialize traceServerPhases : Bool ← do
  return (← IO.getEnv "VBP_PREVIEW_SERVER_PHASES") == some "1"

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
Four monotonic clock reads measure contiguous server preparation phases. No
separate build, rendering traversal, per-node instrumentation, or document cache is added.
The document phase includes cursor lookup in Verso's retained source syntax.
Set `VBP_PREVIEW_SERVER_PHASES=1` on the Lean server for a diagnostic split of
that phase and response encoding. This does not change the preview wire format. -/
meta def previewDocumentWithEncoding (pos : Lsp.Position)
    (encode : Preview → Except String String) : RequestM (RequestTask String) := do
  let encodeReply := fun preview => match encode preview with
    | .ok source => pure source
    | .error message => throw ⟨.internalError, s!"Cannot encode preview: {message}"⟩
  let started ← IO.monoNanosNow
  let editorDocument ← RequestM.readDoc
  RequestM.bindWaitFindSnap editorDocument (·.isAtEnd)
    (notFoundX := throw ⟨.invalidParams, "The Blueprint document is still elaborating"⟩)
    (x := fun snap => do
      let snapshotReady ← IO.monoNanosNow
      let checked : ServerTask Kernel.Environment := snap.env.checked
      RequestM.mapTaskCostly checked fun _ => do
        let checkedReady ← IO.monoNanosNow
        RequestM.checkCancelled
        let name := Verso.Doc.docName editorDocument.meta.mod
        if !(snap.env.contains name) then
          return ← encodeReply (Preview.unavailable "This module has no Verso document")
        let part ← match evalManualPart snap.env snap.cmdState.scopes.head!.opts name with
          | .ok part => pure part
          | .error message => throw ⟨.internalError, s!"Could not evaluate the Blueprint: {message}"⟩
        let partReady ← if traceServerPhases then IO.monoNanosNow else pure checkedReady
        let source := Verso.Doc.Concrete.docEnvironmentExt.getState snap.env
        let finished := source.partState.partContext.toPartFrame.close
          editorDocument.meta.text.source.rawEndPos
        let focus := Source.focusAt finished (editorDocument.meta.text.lspPosToUtf8Pos pos)
        let evaluated ← IO.monoNanosNow
        RequestM.checkCancelled
        let cursorToken := s!"{pos.line}:{pos.character}"
        let reply ← encodeReply (Preview.ready {
          version := editorDocument.meta.version
          correlationId := s!"{editorDocument.meta.version}:{cursorToken}"
          cursorToken
          focus
          serverTiming? := some {
            snapshotWaitNanos := snapshotReady - started
            checkedWaitNanos := checkedReady - snapshotReady
            evaluationNanos := evaluated - checkedReady
          }
          document := part
        })
        if traceServerPhases then
          let encoded ← IO.monoNanosNow
          IO.eprintln s!"VBP preview server phases version={editorDocument.meta.version} \
            snapshotWaitNanos={snapshotReady - started} checkedWaitNanos={checkedReady - snapshotReady} \
            evaluateNanos={partReady - checkedReady} focusNanos={evaluated - partReady} \
            encodeNanos={encoded - evaluated}"
        pure reply)

/-- Standard String endpoint, retaining the default Preview encoding. -/
@[server_rpc_method]
meta def previewDocument (pos : Lsp.Position) : RequestM (RequestTask String) :=
  previewDocumentWithEncoding pos (fun preview => .ok preview.encode)

end VersoBlueprint.Experimental.VirPreview.Server
