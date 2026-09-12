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

@[vir_export]
def createComponent (method : String) : RuntimeM (Js (Component RpcInput)) :=
  createRpcComponent method

@[vir_export]
def render (component : Js (Component RpcInput)) (input : RpcInput) : ReactM (Js Node) := do
  Node.component component (← LeanRef.toJSL input)

end VersoBlueprintVirTests.StringPreview
