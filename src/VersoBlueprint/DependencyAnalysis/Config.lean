/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

namespace Informal.DependencyAnalysis

open Lean

/-- Which unassociated declarations inference may expand, at every hop. -/
inductive HelperExpansion where
  | none
  | all
  | some (symbols : Array Name)
deriving Inhabited, Repr, BEq

-- Options already have the required command/section scoping and propagate into
-- document elaboration. Store resolved names structurally, not as user strings
-- to re-resolve in a later namespace. This key is deliberately not exposed as a
-- scalar `set_option`: the command below supplies the typed authoring surface.
private def expansionKey : Name := `verso.blueprint.helperExpansion

private instance : KVMap.Value HelperExpansion where
  toDataValue
    | .none => .ofSyntax (mkNode `HelperExpansion.none #[])
    | .all => .ofSyntax (mkNode `HelperExpansion.all #[])
    | .some names => .ofSyntax (mkNode `HelperExpansion.some (names.map (mkIdent · |>.raw)))
  ofDataValue?
    | .ofSyntax (.node _ kind args) =>
      if kind == `HelperExpansion.none && args.isEmpty then some .none
      else if kind == `HelperExpansion.all && args.isEmpty then some .all
      else if kind == `HelperExpansion.some && args.all Syntax.isIdent then
        some (.some (args.map Syntax.getId))
      else none
    | _ => none

def HelperExpansion.set (opts : Options) (policy : HelperExpansion) : Options :=
  opts.set expansionKey policy

def getHelperExpansion : CoreM HelperExpansion := do
  let opts ← getOptions
  if !opts.contains expansionKey then return .none
  let some policy := opts.get? (α := HelperExpansion) expansionKey
    | throwError "Invalid internal Blueprint helper expansion configuration"
  return policy

def HelperExpansion.permits : HelperExpansion → (Name → Bool)
  | .none => fun _ => false
  | .all => fun _ => true
  | .some symbols =>
    let names := NameSet.ofArray symbols
    names.contains

declare_syntax_cat blueprintHelperExpansion
syntax "." &"none" : blueprintHelperExpansion
syntax "." &"all" : blueprintHelperExpansion
syntax "." &"some" "#[" ident,* "]" : blueprintHelperExpansion

/--
Configure expansion of unassociated helpers during automatic dependency inference.
Use `.none` (the default), `.all`, or `.some #[decl₁, decl₂]`.
This does not enable `autoDeps`. Settings obey section/namespace scope and Lean's
ordinary `in` command scoping; they are not exported to importing modules.
-/
syntax (name := setBlueprintHelperExpansion)
  "set_blueprint_helper_expansion " blueprintHelperExpansion : command

open Lean.Elab.Command in
elab_rules : command
  | `(set_blueprint_helper_expansion $config:blueprintHelperExpansion) => do
    let policy ← match config with
      | `(blueprintHelperExpansion| .none) => pure HelperExpansion.none
      | `(blueprintHelperExpansion| .all) => pure HelperExpansion.all
      | `(blueprintHelperExpansion| .some #[$symbols:ident,*]) => do
        let names ← symbols.getElems.mapM fun symbol =>
          liftCoreM <| Lean.Elab.realizeGlobalConstNoOverloadWithInfo symbol
        pure <| HelperExpansion.some names
      | _ => Lean.Elab.throwUnsupportedSyntax
    -- Resolve the whole list before changing scope, so errors are atomic.
    modifyScope fun scope => { scope with opts := policy.set scope.opts }

end Informal.DependencyAnalysis
