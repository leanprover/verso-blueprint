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
    -- Metadata (including source syntax) is definitionally irrelevant. Original
    -- source bytes are bound separately; never expand metadata syntax here.
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
  private provider : String
  private state : IO.Ref State

/-- Pin exactly the current checked environment and provider identity. -/
def newSession (provider : String) : CoreM Session := do
  return ⟨← getEnv, provider, ← IO.mkRef {}⟩

/-- Inspectable size counters for bounded regression tests, not a persistence API. -/
def Session.sizes (session : Session) : IO (Nat × Nat) := do
  let state ← session.state.get
  return (state.expressions.expressions.size, state.declarations.size)

private def unavailable (name : Name) (message : String) : Diagnostic :=
  { code := "semantic-context-unavailable", subject := name.toString, message }

/-- Hash each newly reached declaration once. SCC condensation handles mutual
blocks and inductive/constructor back-links. Missing/hidden bodies fail closed;
no footprint or previous capture fills in unavailable semantics. -/
def Session.context (session : Session) (project : Name) (roots : Array Name) :
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
  let mut state ← session.state.get
  let mut todo := roots
  let mut seen : NameSet := {}
  let mut entries : Std.HashMap Name (String × Array Name) := {}
  let env := session.environment
  while !todo.isEmpty do
    let name := todo.back!
    todo := todo.pop
    if seen.contains name || state.declarations.contains name then continue
    seen := seen.insert name
    let some info := env.checked.get.find? name
      | return .error <| unavailable name "Semantic dependency is not in the current checked environment"
    let body ← match Data.ConstantInfo.blueprintBodyAccess env info with
      | .available value => pure (some value)
      | .absent => pure none
      | .unavailable => return .error <| unavailable name "Imported semantic dependency body is unavailable"
    if info.type.hasFVar || info.type.hasMVar || info.type.hasLevelMVar ||
        body.any (fun value => value.hasFVar || value.hasMVar || value.hasLevelMVar) then
      return .error <| unavailable name "Checked semantic declaration contains unresolved variables"
    let encode : StateM Expressions (String × Array Name) := do
      let (kind, extra) ← shape info
      let type ← expressionDigest info.type
      let value ← match body with
        | some value => pure <| SHA256.tagged "lean.body.present.v1" #[← expressionDigest value]
        | none => pure <| SHA256.tagged "lean.body.absent.v1" #[]
      return (SHA256.tagged "lean.declaration.v1"
        #[Vir.nameKey name, reprStr (info.levelParams.map Vir.nameKey), type, value, toString info.isUnsafe, kind], extra)
    let ((payload, extra), expressions) := encode.run state.expressions
    state := { state with expressions }
    let dependencies := info.type.getUsedConstants ++
      (body.map Expr.getUsedConstants).getD #[] ++ extra
    entries := entries.insert name (payload, dependencies)
    todo := todo ++ dependencies
  if !entries.isEmpty then
    -- Pass only touched cached terminals, not the whole accumulated session.
    let terminals := entries.fold (init := {}) fun out _ (_, dependencies) =>
      dependencies.foldl (fun out name => match state.declarations[name]? with
        | some digest => out.insert name digest
        | none => out) out
    let graph := Merkle.graph entries.keysArray Vir.nameKey
      (fun name => (entries[name]!).1) (fun name => (entries[name]!).2) terminals
    let declarations ← match graph with
      | .ok declarations => pure declarations
      | .error message => return .error { code := "invalid-semantic-graph", subject := "native", message }
    let combined := declarations.fold (init := state.declarations) (fun out name digest => out.insert name digest)
    state := { state with declarations := combined }
  session.state.set state
  let roots := (roots.map fun name => (Vir.nameKey name, state.declarations[name]!)).qsort (fun a b => a.1 < b.1)
  let rootParts := roots.foldl (fun out item => if out.back? == some item then out else out.push item)
    (#[] : Array (String × String))
  return .ok <| SHA256.tagged "lean.semantic-context.v1"
    (#[Vir.nameKey project, Lean.versionString, Lean.githash, session.provider] ++
      rootParts.map (fun (name, digest) => SHA256.tagged "lean.root.v1" #[name, digest]))

end Informal.Validation.NativeLean.Semantic
