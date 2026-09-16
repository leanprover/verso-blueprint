/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module
public meta import VersoBlueprintVir.Preview.Server

public section
namespace FirJsonPreview.Server
open Lean Server VersoBlueprint.Experimental.VirPreview

/-- Emit the existing Document codec directly, with no Preview envelope or
browser-side reconstruction. Snapshot/evaluation policy is unchanged. -/
@[server_rpc_method]
meta def previewDocument (pos : Lsp.Position) : RequestM (RequestTask String) :=
  VersoBlueprint.Experimental.VirPreview.Server.previewDocumentWithEncoding pos fun
    | .ready document => .ok document.encode
    | .loading message | .unavailable message | .error message => .error message

end FirJsonPreview.Server
