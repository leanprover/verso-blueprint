/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoManual.Basic

public section

namespace VersoBlueprint.Experimental.VirPreview

/--
Optional server-side durations for this response, measured with one monotonic
clock. Snapshot waits include scheduling and any remaining document work;
these are not pure elaboration times and exclude JSON encoding and transport.
-/
structure ServerTiming where
  snapshotWaitNanos : Nat
  checkedWaitNanos : Nat
  evaluationNanos : Nat
  deriving BEq, Lean.ToJson, Lean.FromJson

def ServerTiming.preparationNanos (timing : ServerTiming) : Nat :=
  timing.snapshotWaitNanos + timing.checkedWaitNanos + timing.evaluationNanos

/--
Renderer-owned input for one live Verso Manual document.

Blueprint documents already use the Manual genre, so the preview keeps that
document intact rather than maintaining a second projected representation.
`focus` uses the renderer paths exposed as `data-verso-block` attributes.
-/
structure Document where
  version : Nat
  correlationId : String := ""
  cursorToken : String := ""
  focus : Option String := none
  serverTiming? : Option ServerTiming := none
  document : _root_.Verso.Doc.Part _root_.Verso.Genre.Manual
  deriving BEq, Lean.ToJson, Lean.FromJson

namespace Document

/-- Compact ordinary JSON representation of a document response. -/
def encode (document : Document) : String :=
  (Lean.toJson document).compress

/-- Decode a renderer document from its ordinary RPC JSON representation. -/
def decode (source : String) : Except String Document := do
  let json ← Lean.Json.parse source
  Lean.fromJson? json

end Document

/--
One update of the long-lived preview session.

Keeping loading and failure states in the typed payload lets an infoview client
retain React state while the document at the cursor is temporarily unavailable.
-/
inductive Preview where
  | loading (message : String)
  | unavailable (message : String)
  | ready (document : Document)
  | error (message : String)
  deriving BEq, Lean.ToJson, Lean.FromJson

namespace Preview

/-- Compact typed-RPC representation of a preview update. -/
def encode (preview : Preview) : String :=
  (Lean.toJson preview).compress

/-- Decode a preview update from its ordinary RPC JSON representation. -/
def decode (source : String) : Except String Preview := do
  let json ← Lean.Json.parse source
  Lean.fromJson? json

/-- The current renderable document, when this update carries one. -/
def document? : Preview → Option Document
  | .ready document => some document
  | _ => none

end Preview

end VersoBlueprint.Experimental.VirPreview
