/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module
public meta import VersoBlueprintVir.Preview.Server
public meta import VersoBlueprintVirTests.NativeSession.UpstreamJson.Codec

public section
namespace CheckedJsonPreview.Server
open Lean Server VersoBlueprint.Experimental.VirPreview

/-- Check the exact-number domain before JSON.parse could round the payload. -/
@[server_rpc_method]
meta def previewDocument (pos : Lsp.Position) : RequestM (RequestTask String) :=
  VersoBlueprint.Experimental.VirPreview.Server.previewDocumentWithEncoding pos fun preview =>
    (Lean.Vir.JsonValue.encode preview).map Json.compress

end CheckedJsonPreview.Server
