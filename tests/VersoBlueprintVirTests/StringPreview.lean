/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Rpc
meta import Vir.Attributes

public section

namespace VersoBlueprintVirTests.StringPreview

open Lean.Vir Lean.Vir.React VersoBlueprint.Experimental.VirPreview
open scoped Lean.Vir.Js

@[vir_export]
def createComponent (method : String) : RuntimeM (FunctionComponent (Props.WithData RpcInput)) :=
  createRpcComponent method

@[vir_export]
def render (component : FunctionComponent (Props.WithData RpcInput)) (input : RpcInput) : ReactM (Js Node) := do
  let props ← Props.WithData.make (← LeanRef.toJSL input)
  Node.functionComponent component props (← js#[])

end VersoBlueprintVirTests.StringPreview
