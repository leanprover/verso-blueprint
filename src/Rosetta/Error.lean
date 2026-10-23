/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Data.Json

namespace Rosetta
open Lean

/-- Cleanup succeeds only when the child is reaped and every IO worker stops.
An incomplete report is retained for repeated/concurrent close callers. -/
structure CloseReport where
  reaped : Bool := false
  workersStopped : Bool := false
  forced : Bool := false
  errors : Array String := #[]
  deriving Inhabited, Repr

def CloseReport.complete (report : CloseReport) : Bool :=
  report.reaped && report.workersStopped && report.errors.isEmpty

/-- Operational failures are distinct from valid empty results. Server codes
are open integers, and absent error data differs from explicit JSON null.
Only the constructors/fields, not their rendered wording, are machine APIs. -/
inductive ClientError where
  | cancelled (method : String)
  | deadline (method : String)
  | closed
  | staleDocument (uri : String) (expected : Int) (actual? : Option Int)
  | invalidInput (detail : String)
  | queueFull
  | pendingFull
  | unsupported (feature : String)
  | disconnected
  | protocol (detail : String)
  | io (cause : IO.Error)
  | server (code : Int) (message : String) (data? : Option Json)
  | cleanup (report : CloseReport) (original? : Option ClientError)

partial def ClientError.toString : ClientError → String
    | .cancelled method => s!"request cancelled: {method}"
    | .deadline method => s!"request deadline exceeded: {method}"
    | .closed => "client is closing or closed"
    | .staleDocument uri expected actual? =>
      s!"stale document handle: {uri} (expected {expected}, current {repr actual?})"
    | .invalidInput detail => s!"invalid input: {detail}"
    | .queueFull => "outbound queue capacity exceeded"
    | .pendingFull => "pending request capacity exceeded"
    | .unsupported feature => s!"unsupported: {feature}"
    | .disconnected => "LSP transport disconnected or retired"
    | .protocol detail => s!"LSP protocol error: {detail}"
    | .io cause => cause.toString
    | .server code message data? =>
      s!"server error {code}: {message}" ++ (data?.map (fun data => s!" ({data.compress})") |>.getD "")
    | .cleanup report original? =>
      let cleanup := s!"session cleanup incomplete: {repr report}"
      original?.map (fun original => s!"{ClientError.toString original}; {cleanup}") |>.getD cleanup

instance : ToString ClientError := ⟨ClientError.toString⟩

instance : Repr ClientError where
  reprPrec error _ := repr error.toString

/-- Standard IO can be used in session/profile actions without erasing the
original IO error. Conversion back to IO belongs at the application's boundary. -/
instance : MonadLift IO (EIO ClientError) where
  monadLift := IO.toEIO ClientError.io

end Rosetta
