# Rosetta API and structured failures

Experimental APIs for the standalone Rosetta core and VersoRosetta bridge.
See the [package overview](../README.md) for installation, toolchain, and runtime requirements.

## The retained surface

`import Rosetta` exposes the Lean/Std-only core. The main application operation
is now:

```lean
Rosetta.analyze : Array ContextProfile → Array Request → EIO ClientError Bundle
```

Requests describe authored code or references and their source origins.
Profiles provide language/server configuration, project membership, reference
syntax, and `collectDiagnostics : Document → EIO ClientError DiagnosticEvidence`.
Analysis owns the server scopes and returns portable snapshots. `Outcome.failed`
inside a saved snapshot remains human-readable feature-failure text; live
operational errors remain typed through analysis and profile callbacks.

| Entry point | Contract |
| --- | --- |
| `Client.withSession config action` | Run an `EIO ClientError` action and own cleanup on success/failure |
| `Client.start config` | Acquire a manually owned client; returns `EIO ClientError Client` |
| `client.request method params timeoutMs cancel?` | Workspace/session RPC; return the JSON result or throw `ClientError` |
| `client.notify method params` | Admit a workspace/session notification to the bounded queue |
| `client.openDocument uri languageId text` | Return a handle for the admitted document version |
| `document.request method params timeoutMs cancel?` | RPC with matching URI/version, checked at admission and delivery |
| `document.change text` | Admit an edit and return its replacement handle |
| `document.diagnostics` | Read the snapshot through a current handle |
| `document.close` | Close that version, rejecting stale handles |
| `client.close` | Return a shared `CloseReport` in `BaseIO`, including incomplete cleanup |

Fallible operations above use `EIO ClientError`. Deadlines and caller-owned
cancellation tokens remain optional request parameters. The client-wide
capabilities, stderr, and notification observations are `BaseIO` operations.
`document.client` is a plain accessor for session-wide readiness observations;
it does not replace versioned document admission.

Manual start/close and scoped ownership are both retained because they cover
different lifetimes. Workspace and document requests remain separate because
only the latter carry a versioned document handle.

Source composition (`compose`, `Projection.mapRange`), portable bundle
validation/matching (`Bundle.validate`, `Bundle.find`), and the Verso bridge
retain their existing responsibilities. The current `VersoRosetta.collect` and
`VersoRosetta.enrich` entry points operate on Manual parts and remain pure.

## Workspace references and highlighted definitions

`Client.workspaceSymbols query` wraps `workspace/symbol`, including deferred
locations via `workspaceSymbol/resolve`. `Document.definitions position` wraps
`textDocument/definition` and preserves both full and selection ranges from
LocationLink. `Document.semanticTokens text range?` requests and decodes semantic tokens
against the exact opened document text. When a range is supplied and the server
supports range tokens, it requests only that range; otherwise it requests full
document tokens.
Rosetta advertises both request forms and never sends an unadvertised full
request to a range-only server. A `null` token result means no coloring; the
source slice is still preserved. The `text` argument must be the exact text
used to open the document version.

For a named reference, use:

```lean
Client.withSession config fun client => do
  -- Wait for the project's server to finish loading, when necessary.
  client.sourceDefinition "rust" "EdwardsPoint::compress" "::"
```

`Client.sourceDefinition` searches by the final component, filters fuzzy results
to an exact name and optional container supplied by the author, and requires a
unique location. It asks `definition` at that location, follows the returned
file URI, and highlights its returned range. The result is a
`HighlightedDefinition` with the original `DefinitionTarget`, language ID, and
lossless text pieces carrying semantic token types and modifiers. Token spans
intersecting the range boundaries are clipped, preserving Unicode and CRLF.
Source files are read only. Non-file URIs are reported as unsupported.

The lower-level operations `Client.workspaceDefinition` and
`Client.highlightDefinition` can be used separately. Missing or ambiguous names
produce `ClientError.invalidInput`; protocol, server, and unsupported-feature
errors keep their existing types. A Location-only server controls the source
extent it returns; Rosetta does not invent a larger declaration range.

This is workspace symbol discovery, not compiler resolution of expressions or
imports. Qualification matches the server's `containerName` exactly; supported
container depth is determined by the server. For a Rust expression in a known
scope, use `Document.definitions` or the existing `ContextProfile` analysis.

Initialization options remain caller-owned. For example, rust-analyzer needs
`workspace.symbol.search.kind = "all_symbols"` to include methods. Workspace
indexing readiness is also server-specific. `Client.waitForNotification method
predicate timeoutMs` provides a bounded wait on the latest notification of that
method in the retained trace, so a caller can await rust-analyzer's `experimental/serverStatus` with
`quiescent = true`. The generic API contains no Rust names, source paths, or
Rust syntax assumptions; the author supplies the reference separator.
`Client.notifications` retains the latest 512 general notifications, with an
eviction count. Diagnostics are stored separately in `Document.diagnostics`.
A readiness message evicted by later traffic cannot satisfy this wait; callers
that need a stronger readiness barrier should use a server-specific request.

## Error contract

`ClientError` is the machine-facing failure interface:

| Constructor | Meaning |
| --- | --- |
| `cancelled method` | Caller cancellation |
| `deadline method` | The operation's monotonic deadline elapsed |
| `closed` | Closing/closed client rejected work |
| `staleDocument uri expected actual?` | Handle version differs; `none` means the URI is closed |
| `invalidInput detail` | Invalid local input, query ownership, plan, or saved-data validation |
| `queueFull` / `pendingFull` | Outbound admission or pending-request capacity exhausted |
| `unsupported feature` | Required synchronization/encoding is unsupported |
| `disconnected` | Transport EOF or retirement |
| `protocol detail` | Malformed framing, JSON-RPC, or server feature data |
| `io cause` | Original `IO.Error`, preserving its constructor and fields |
| `server code message data?` | A valid server error response; arbitrary integer codes survive |
| `cleanup report original?` | Incomplete scoped cleanup, retaining any original typed failure |

Absent server error data is `none`; explicit JSON null is `some Json.null`.
A successful JSON null result stays a successful result. A valid server error
does not poison the transport or cancel an already completed request. Malformed
responses fail the transport as protocol errors.

Normal `IO` actions lift into `EIO ClientError` using `ClientError.io`, including
inside session/profile callbacks. Converting back to `IO` is explicit at the
application boundary. For example, a command-line entry point can choose:

```lean
import Rosetta
open Rosetta

def analyzeIO (profiles : Array ContextProfile) (requests : Array Request) : IO Bundle :=
  (analyze profiles requests).toIO (IO.userError ∘ toString)
```

Library callers can instead catch and match `ClientError`, or use the standard
`EIO.toBaseIO` to obtain `Except ClientError α`. `EIO.asTask` preserves the error
type across concurrent operations. Rendered error wording is diagnostic text,
not a machine interface. The API remains subject to the project's normal
no-compatibility policy between revisions.

## Migration from the embedded prototype

- Replace `.call` with `.request`; existing `.request` users now receive the
  result directly instead of the envelope.
- Change client/analysis/profile action signatures to `EIO ClientError` and use
  constructor matching instead of parsing `IO.Error` text.
- Replace `document.withClient f` with `f document.client`.
- Manual cleanup returns `BaseIO CloseReport`; scoped cleanup raises
  `ClientError.cleanup` if that report is incomplete.
