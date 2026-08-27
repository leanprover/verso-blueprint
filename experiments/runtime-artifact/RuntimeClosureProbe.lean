import Lean.Compiler.IR.CompilerM
import Lean.Util.FoldConsts
import FLTBlueprint

open Lean

namespace RuntimeClosureProbe

private def callsOfIRExpr : IR.Expr → Array Name
  | .fap fn _ | .pap fn _ => #[fn]
  | _ => #[]

private partial def callsOfIRBody : IR.FnBody → Array Name
  | .vdecl _ _ value body => callsOfIRExpr value ++ callsOfIRBody body
  | .jdecl _ _ value body => callsOfIRBody value ++ callsOfIRBody body
  | .set _ _ _ body
  | .setTag _ _ body
  | .uset _ _ _ body
  | .sset _ _ _ _ _ body
  | .inc _ _ _ _ body
  | .dec _ _ _ _ body
  | .del _ body => callsOfIRBody body
  | .case _ _ _ alts => alts.flatMap fun alt => callsOfIRBody alt.body
  | .ret _ | .jmp _ _ | .unreachable => #[]

structure IRClosure where
  seen : Std.HashSet Name := {}
  internal : Std.HashSet Name := {}
  externs : Std.HashSet Name := {}
  missing : Std.HashSet Name := {}

private partial def visitIR (env : Environment) (pending : List Name)
    (state : IRClosure := {}) : IRClosure :=
  match pending with
  | [] => state
  | name :: pending =>
      if state.seen.contains name then
        visitIR env pending state
      else
        let state := { state with seen := state.seen.insert name }
        match IR.findEnvDecl env name with
        | none => visitIR env pending { state with missing := state.missing.insert name }
        | some (.extern ..) =>
            visitIR env pending { state with externs := state.externs.insert name }
        | some (.fdecl _ _ _ body _) =>
            let calls := callsOfIRBody body
            visitIR env (calls.toList ++ pending)
              { state with internal := state.internal.insert name }

structure ExprClosure where
  seen : Std.HashSet Name := {}
  definitions : Std.HashSet Name := {}
  leaves : Std.HashSet Name := {}
  missing : Std.HashSet Name := {}

private partial def visitExpr (env : Environment) (pending : List Name)
    (state : ExprClosure := {}) : ExprClosure :=
  match pending with
  | [] => state
  | name :: pending =>
      if state.seen.contains name then
        visitExpr env pending state
      else
        let state := { state with seen := state.seen.insert name }
        match env.find? name with
        | none => visitExpr env pending { state with missing := state.missing.insert name }
        | some (.thmInfo ..) =>
            visitExpr env pending { state with leaves := state.leaves.insert name }
        | some info =>
            match info.value? (allowOpaque := true) with
            | none => visitExpr env pending { state with leaves := state.leaves.insert name }
            | some value =>
                visitExpr env (value.getUsedConstants.toList ++ pending)
                  { state with definitions := state.definitions.insert name }

private def sortedNames (names : Std.HashSet Name) : Array Name :=
  names.toArray.qsort fun left right => left.toString < right.toString

private def moduleNameFor (env : Environment) (name : Name) : String :=
  match env.getModuleIdxFor? name with
  | some idx => env.header.moduleNames[idx]!.toString
  | none => "<local-or-runtime>"

private def nodeJson (env : Environment) (name : Name) : Json :=
  .mkObj [
    ("name", .str name.toString),
    ("module", .str (moduleNameFor env name))
  ]

private def nodesJson (env : Environment) (names : Std.HashSet Name) : Json :=
  .arr <| (sortedNames names).map (nodeJson env)

private def closureJson (env : Environment) (root : Name) : Json :=
  let ir := visitIR env [root]
  let expr := visitExpr env [root]
  let directIRCalls :=
    match IR.findEnvDecl env root with
    | some (.fdecl _ _ _ body _) =>
        (callsOfIRBody body).foldl (init := {}) fun calls name => calls.insert name
    | _ => {}
  .mkObj [
    ("schema", .str "verso-blueprint-constant-closure-v1"),
    ("root", .str root.toString),
    ("importedModules", .num env.header.modules.size),
    ("ir", .mkObj [
      ("reachable", .num ir.seen.size),
      ("directCalls", nodesJson env directIRCalls),
      ("internal", nodesJson env ir.internal),
      ("extern", nodesJson env ir.externs),
      ("missing", nodesJson env ir.missing)
    ]),
    ("expression", .mkObj [
      ("reachable", .num expr.seen.size),
      ("definitions", nodesJson env expr.definitions),
      ("leaves", nodesJson env expr.leaves),
      ("missing", nodesJson env expr.missing)
    ])
  ]

private unsafe def saveRuntimeBundle (env : Environment) (root : Name)
    (outputPath : System.FilePath) : IO Unit := do
  let closure := visitIR env [root]
  let declarations := (sortedNames closure.seen).filterMap (IR.findEnvDecl env)
  let declarations := declarations.qsort fun left right =>
    Name.quickLt left.name right.name
  let some rootInfo := env.find? root
    | throw <| IO.userError s!"runtime root declaration not found: {root}"
  let irEntries : Array EnvExtensionEntry := unsafeCast declarations
  let data : ModuleData := {
    isModule := false
    imports := #[]
    constNames := #[root]
    constants := #[rootInfo]
    extraConstNames := declarations.map (·.name) |>.filter (· != root)
    entries := #[(IR.declMapExt.name, irEntries)]
  }
  saveModuleData outputPath `VersoBlueprint.RuntimeBundle data

run_meta do
  let some outputPath ← IO.getEnv "VBP_CONSTANT_CLOSURE_OUT"
    | throwError "VBP_CONSTANT_CLOSURE_OUT is not set"
  let env ← getEnv
  IO.FS.writeFile outputPath
    (closureJson env (Verso.Doc.docName `FLTBlueprint)).pretty
  if let some bundleOutputPath ← IO.getEnv "VBP_RUNTIME_BUNDLE_OUT" then
    unsafe saveRuntimeBundle env (Verso.Doc.docName `FLTBlueprint) bundleOutputPath

end RuntimeClosureProbe
