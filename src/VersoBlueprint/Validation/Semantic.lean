/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Meta.Sym.ExprPtr
import Vir.Package.Name
import VersoBlueprint.Validation
import VersoBlueprint.ProvedStatus
import VersoBlueprint.Util.Merkle

/-! Capture-local fingerprints of the checked semantic graph. SHA-256 collision
resistance is an explicit assumption for freshness, not a proof checker. No
native success is cached here. Pointer identity is only a memo-table accelerator;
it is never serialized or used as semantic identity. -/

namespace Informal.Validation.NativeLean.Semantic
open Lean Realizations

private structure Expressions where
  expressions : Std.HashMap Meta.Sym.ExprPtr String := {}
  levels : LevelMap String := {}

private partial def levelDigest (level : Level) : StateM Expressions String := do
  if let some digest := (← get).levels[level]? then return digest
  let (tag, parts) ← match level with
    | .zero => pure ("zero", #[])
    | .succ u => pure ("succ", #[← levelDigest u])
    | .max u v => pure ("max", #[← levelDigest u, ← levelDigest v])
    | .imax u v => pure ("imax", #[← levelDigest u, ← levelDigest v])
    | .param name => pure ("param", #[Vir.nameKey name])
    | .mvar name => pure ("mvar", #[Vir.nameKey name.name])
  let digest := SHA256.tagged ("lean.level.v1." ++ tag) parts
  modify fun state => { state with levels := state.levels.insert level digest }
  return digest

private partial def expressionDigest (expression : Expr) : StateM Expressions String := do
  if let some digest := (← get).expressions[(⟨expression⟩ : Meta.Sym.ExprPtr)]? then return digest
  let digest ← match expression with
    -- Metadata (including source syntax) is definitionally irrelevant. Keep
    -- source locations and formatting outside semantic review identity.
    | .mdata _ body => expressionDigest body
    | other => do
      let (tag, parts) ← match other with
        | .bvar index => pure ("bvar", #[toString index])
        | .fvar id => pure ("fvar", #[Vir.nameKey id.name])
        | .mvar id => pure ("mvar", #[Vir.nameKey id.name])
        | .sort level => pure ("sort", #[← levelDigest level])
        | .const name levels => pure ("const", #[Vir.nameKey name] ++ (← levels.toArray.mapM levelDigest))
        | .app fn arg => pure ("app", #[← expressionDigest fn, ← expressionDigest arg])
        | .lam name type body binder => pure ("lam", #[Vir.nameKey name, reprStr binder,
            ← expressionDigest type, ← expressionDigest body])
        | .forallE name type body binder => pure ("forall", #[Vir.nameKey name, reprStr binder,
            ← expressionDigest type, ← expressionDigest body])
        | .letE name type value body nondep => pure ("let", #[Vir.nameKey name, toString nondep,
            ← expressionDigest type, ← expressionDigest value, ← expressionDigest body])
        | .lit value => pure ("literal", #[reprStr value])
        | .proj name index body => pure ("projection", #[Vir.nameKey name, toString index, ← expressionDigest body])
        | .mdata _ _ => unreachable!
      pure <| SHA256.tagged ("lean.expr.v1." ++ tag) parts
  modify fun state => { state with expressions := state.expressions.insert ⟨expression⟩ digest }
  return digest

/-- Structural expression identity, modulo metadata, independent of allocation
sharing. Open-expression IDs are encoded, but checked declarations below reject
open terms. This descriptor never substitutes for kernel/definitional checks. -/
def fingerprint (expression : Expr) : String :=
  (expressionDigest expression).run' {}

private def shape (info : ConstantInfo) : StateM Expressions (String × Array Name) := do
  let (tag, parts, extra) ← match info with
    | .axiomInfo _ => pure ("axiom", #[], #[])
    | .thmInfo value => pure ("theorem", #[reprStr (value.all.map Vir.nameKey)], value.all.toArray)
    | .opaqueInfo value => pure ("opaque", #[reprStr (value.all.map Vir.nameKey)], value.all.toArray)
    | .defnInfo value =>
      let hints := match value.hints with
        | .abbrev => "abbrev"
        | .opaque => "opaque"
        | .regular height => "regular:" ++ toString height
      pure ("definition", #[hints, reprStr value.safety, reprStr (value.all.map Vir.nameKey)], value.all.toArray)
    | .inductInfo value => pure ("inductive", #[reprStr (value.all.map Vir.nameKey), reprStr (value.ctors.map Vir.nameKey),
        reprStr (value.numParams, value.numIndices, value.numNested, value.isRec, value.isReflexive)],
        value.all.toArray ++ value.ctors.toArray)
    | .ctorInfo value => pure ("constructor", #[Vir.nameKey value.induct,
        reprStr (value.cidx, value.numParams, value.numFields)], #[value.induct])
    | .recInfo value => do
      let rules ← value.rules.toArray.mapM fun rule => do
        pure <| SHA256.tagged "lean.recursor.rule.v1" #[Vir.nameKey rule.ctor, toString rule.nfields,
          ← expressionDigest rule.rhs]
      pure ("recursor", #[reprStr (value.all.map Vir.nameKey),
        reprStr (value.numParams, value.numIndices, value.numMotives, value.numMinors, value.k)] ++ rules,
        value.all.toArray ++ value.rules.toArray.flatMap (fun rule => #[rule.ctor] ++ rule.rhs.getUsedConstants))
    | .quotInfo value =>
      let kind := match value.kind with
        | .type => "type"
        | .ctor => "constructor"
        | .lift => "lift"
        | .ind => "induction"
      pure ("quotient", #[kind], #[])
  return (SHA256.tagged ("lean.declaration.shape.v1." ++ tag) parts, extra)

private structure State where
  expressions : Expressions := {}
  declarations : Std.HashMap Name String := {}

/-- The environment is immutable and owned by this capture-local session. No
session survives a capture or supplies evidence; only structural digests are
reused. Calls within a session are sequential. -/
structure Session where
  private mk ::
  private environment : Environment
  private state : IO.Ref State

/-- Pin exactly the current checked environment. -/
def newSession : CoreM Session := do
  return ⟨← getEnv, ← IO.mkRef {}⟩

/-- Inspectable size counters for bounded regression tests, not a persistence API. -/
def Session.sizes (session : Session) : IO (Nat × Nat) := do
  let state ← session.state.get
  return (state.expressions.expressions.size, state.declarations.size)

private def unavailable (name : Name) (message : String) : Diagnostic :=
  { code := "semantic-context-unavailable", subject := name.toString, message }

initialize registerTraceClass `blueprint.capture.semantic

private def Session.collectContext (session : Session) (project : Name) (roots : Array Name)
    (scope : ContentScope) (tracing : Bool) :
    CoreM (Except Diagnostic String) := do
  if project.isAnonymous || roots.isEmpty then
    return .error {
      code := "invalid-semantic-context"
      subject := "native"
      message := "Semantic capture requires explicit project and declaration roots" }
  unless unsafe ptrEq (← getEnv) session.environment do
    return .error {
      code := "semantic-session-mismatch"
      subject := "native"
      message := "Semantic session belongs to another environment snapshot; create a fresh session" }
  -- Transfer the growing expression table directly between encodings. Keeping
  -- it inside a parent record needed for another field aliases it on every
  -- declaration and forces repeated copy-on-write. Publish only after success.
  let initial ← session.state.get
  let mut expressions := initial.expressions
  let mut declarations := initial.declarations
  let mut todo := roots
  let env := session.environment
  let mut ownBodies : Array (Name × Expr) := #[]
  if scope == .implementation then
    for name in roots do
      let some info := env.checked.get.find? name
        | return .error <| unavailable name "Selected implementation is not in the checked environment"
      match Data.ConstantInfo.blueprintBodyAccess env info with
      | .unavailable => return .error <| unavailable name "Selected implementation body is unavailable"
      | .absent => pure ()
      | .available body =>
        if body.hasFVar || body.hasMVar || body.hasLevelMVar then
          return .error <| unavailable name "Selected implementation contains unresolved variables"
        ownBodies := ownBodies.push (name, body)
        todo := todo ++ body.getUsedConstants
  let mut seen : NameSet := {}
  let mut entries : Std.HashMap Name (String × Array Name) := {}
  while !todo.isEmpty do
    let name := todo.back!
    todo := todo.pop
    if seen.contains name || declarations.contains name then continue
    seen := seen.insert name
    let some info := env.checked.get.find? name
      | return .error <| unavailable name "Semantic dependency is not in the current checked environment"
    -- Proof-valued definitions/opaque constants have the same statement boundary
    -- as theorems. Definitions *of propositions* are computational content.
    let proofValued ← match info with
      | .thmInfo _ => pure true
      | .defnInfo _ | .opaqueInfo _ | .axiomInfo _ => Meta.MetaM.run' (Meta.isProp info.type)
      | _ => pure false
    let body ← match (if proofValued then Data.BodyAccess.absent else Data.ConstantInfo.blueprintBodyAccess env info) with
      | .available value => pure (some value)
      | .absent => pure none
      | .unavailable => return .error <| unavailable name "Imported semantic dependency body is unavailable"
    if info.type.hasFVar || info.type.hasMVar || info.type.hasLevelMVar ||
        body.any (fun value => value.hasFVar || value.hasMVar || value.hasLevelMVar) then
      return .error <| unavailable name "Checked semantic declaration contains unresolved variables"
    let encode : StateM Expressions (String × Array Name) := do
      let (kind, extra) ← if proofValued then pure ("proof-type-v2", #[]) else shape info
      let type ← expressionDigest info.type
      let value ← match body with
        | some value => pure <| SHA256.tagged "lean.body.present.v1" #[← expressionDigest value]
        | none => pure <| SHA256.tagged "lean.body.absent.v1" #[]
      return (SHA256.tagged "lean.statement.v2"
        #[Vir.nameKey name, reprStr (info.levelParams.map Vir.nameKey), type, value, toString info.isUnsafe, kind], extra)
    let ((payload, extra), updatedExpressions) := encode.run expressions
    expressions := updatedExpressions
    let dependencies := info.type.getUsedConstants ++
      (body.map Expr.getUsedConstants).getD #[] ++ extra
    entries := entries.insert name (payload, dependencies)
    todo := todo ++ dependencies
    if tracing && (entries.size == 1 || entries.size % 1024 == 0) then
      trace[blueprint.capture.semantic]
        "collected={entries.size} expressions={expressions.expressions.size} pending={todo.size} last={name}"
  if !entries.isEmpty then
    -- Pass only touched cached terminals, not the whole accumulated session.
    let terminals := entries.fold (init := {}) fun out _ (_, dependencies) =>
      dependencies.foldl (fun out name => match declarations[name]? with
        | some digest => out.insert name digest
        | none => out) out
    let graph := Merkle.graph entries.keysArray Vir.nameKey
      (fun name => (entries[name]!).1) (fun name => (entries[name]!).2) terminals
    let computed ← match graph with
      | .ok digests => pure digests
      | .error message => return .error { code := "invalid-semantic-graph", subject := "native", message }
    declarations := computed.fold (init := declarations) (fun out name digest => out.insert name digest)
  let mut rootParts : Array (String × String) := #[]
  for name in roots do
    let statement := declarations[name]!
    let digest ← if scope == .statement then pure statement else do
      let body := ownBodies.find? (·.1 == name) |>.map (·.2)
      let (bodyDigest, updated) := (do
        match body with
        | none => pure <| SHA256.tagged "lean.implementation.absent.v2" #[]
        | some value =>
          let expression ← expressionDigest value
          let dependencies := value.getUsedConstants.map fun n =>
            SHA256.tagged "lean.dependency.v2" #[Vir.nameKey n, declarations[n]!]
          pure <| SHA256.tagged "lean.implementation.body.v2" (#[expression] ++ dependencies)
        : StateM Expressions String).run expressions
      expressions := updated
      pure <| SHA256.tagged "lean.implementation.v2" #[statement, bodyDigest]
    rootParts := rootParts.push (Vir.nameKey name, digest)
  let orderedRoots := rootParts.qsort (fun a b => a.1 < b.1) |>.foldl
    (fun out item => if out.back? == some item then out else out.push item)
    (#[] : Array (String × String))
  session.state.set { expressions, declarations }
  return .ok <| SHA256.tagged "lean.semantic-context.v2"
    (#[Vir.nameKey project, if scope == .statement then "statement" else "implementation"] ++
      orderedRoots.map (fun (name, digest) => SHA256.tagged "lean.root.v2" #[name, digest]))

/-- Hash each newly reached declaration once. SCC condensation handles mutual
blocks and inductive/constructor back-links. Missing/hidden bodies fail closed;
no footprint or previous capture fills in unavailable semantics. Optional tracing
reports work and committed cache sizes, never source bytes or provider inputs. -/
def Session.context (session : Session) (project : Name) (roots : Array Name) (scope : ContentScope := .implementation) :
    CoreM (Except Diagnostic String) := do
  unless ← isTracingEnabledFor `blueprint.capture.semantic do
    return ← session.collectContext project roots scope false
  let before ← session.sizes
  let started ← IO.monoMsNow
  let heartbeats ← IO.getNumHeartbeats
  letI : ExceptToTraceResult Exception (Except Diagnostic String) := ⟨fun
    | .ok (.ok _) => .success
    | .ok (.error _) => .failure
    | .error _ => .error⟩
  withTraceNode `blueprint.capture.semantic (fun result => do
    let outcome := match result with
      | .ok (.ok _) => "complete"
      | .ok (.error _) => "unavailable"
      | .error _ => "exception"
    return m!"{roots} ({repr scope}): {outcome}; elapsedMs={(← IO.monoMsNow) - started} rawHeartbeats={(← IO.getNumHeartbeats) - heartbeats}; committed (expressions,declarations) {before} -> {← session.sizes}") do
    trace[blueprint.capture.semantic] "begin {roots}"
    session.collectContext project roots scope true

end Informal.Validation.NativeLean.Semantic
