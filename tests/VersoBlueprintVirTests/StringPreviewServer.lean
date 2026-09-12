/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public meta import VersoBlueprintVir.Preview.Model
public meta import Lean.Server.Rpc.RequestHandling

public section

namespace StringPreviewServer

open Lean Server VersoBlueprint.Experimental.VirPreview

meta structure Query where
  message : String
  fail : Bool := false
  waitForCancellation : Bool := false
  deriving RpcEncodable

@[server_rpc_method]
meta def preview (query : Query) : RequestM (RequestTask String) := RequestM.asTask do
  -- This fixture mode can finish only when transport cancellation reaches Lean.
  while query.waitForCancellation do
    RequestM.checkCancelled
    IO.sleep 10
  if query.fail then
    throw (RequestError.invalidParams "Preview fixture rejection")
  if query.message == "malformed JSON" then return "{"
  if query.message == "wrong schema" then return "{}"
  let doc ← RequestM.readDoc
  let document : Document := {
    version := doc.meta.version
    correlationId := query.message
    document := .mk #[.text "String RPC preview"] "String RPC preview" none
      #[.para #[.text query.message]] #[]
  }
  return (Preview.ready document).encode

@[server_rpc_method]
meta def wrongType (_query : Query) : RequestM (RequestTask Nat) :=
  RequestM.pureTask (pure 42)

-- rpc-position-a
example : True := by
  trivial

-- rpc-position-b
example : True := by
  trivial

end StringPreviewServer
