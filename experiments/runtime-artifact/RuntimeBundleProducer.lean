import Lean.Compiler.IR.CompilerM
import FLTBlueprint

open Lean

namespace RuntimeBundleProducer

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

private partial def runtimeClosure (env : Environment) (pending : List Name)
    (seen : Std.HashSet Name := {}) : Std.HashSet Name :=
  match pending with
  | [] => seen
  | name :: pending =>
      if seen.contains name then
        runtimeClosure env pending seen
      else
        let seen := seen.insert name
        match IR.findEnvDecl env name with
        | some (.fdecl _ _ _ body _) =>
            runtimeClosure env ((callsOfIRBody body).toList ++ pending) seen
        | some (.extern ..) | none => runtimeClosure env pending seen

private unsafe def saveRuntimeBundle (env : Environment) (root : Name)
    (outputPath : System.FilePath) : IO Unit := do
  let declarations := (runtimeClosure env [root]).toArray.filterMap (IR.findEnvDecl env)
    |>.qsort fun left right => Name.quickLt left.name right.name
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
  let some outputPath ← IO.getEnv "VBP_RUNTIME_BUNDLE_OUT"
    | throwError "VBP_RUNTIME_BUNDLE_OUT is not set"
  let env ← getEnv
  unsafe saveRuntimeBundle env (Verso.Doc.docName `FLTBlueprint) outputPath

end RuntimeBundleProducer
