/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module
public meta import VersoBlueprintVir.Preview.Server
public meta import VersoBlueprintVirTests.NativeSession.UpstreamJson.Codec

public section
namespace MatchedPreview.Server
open Lean Server VersoBlueprint.Experimental.VirPreview

/-- Both backends receive the same checked Document JSON, not runtime objects. -/
@[server_rpc_method]
meta def previewDocument (pos : Lsp.Position) : RequestM (RequestTask String) :=
  VersoBlueprint.Experimental.VirPreview.Server.previewDocumentWithEncoding pos fun
    | .ready document => (Lean.Vir.JsonValue.encode document).map Json.compress
    | .loading message | .unavailable message | .error message => .error message

end MatchedPreview.Server
