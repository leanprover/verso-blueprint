> Historical design record. APIs and package layout below are superseded.
> Use the [current integration guide](../../ROSETTA_API.md) and the standalone Rosetta API.

# Parley lifecycle review

Date: 2026-10-23. This follows the [document slice](VERSO_LSP_DOCUMENT_SLICE.md).
The core and bridge remain local experimental libraries; this does not publish
a package or update PR #63.

API update: the subsequent [structured-error revision](../../ROSETTA_API.md) replaces
the `request`/`call` pair below with one result-returning `request`, uses
`EIO ClientError` through analysis and profile actions, and removes
`Document.withClient`. The lifecycle evidence and timings here describe the
earlier revision; the linked guide describes the current API.

## Decisions implemented

The original client's state mutex enclosed blocking pipe writes, including
replies to server requests and cancellation notifications. A peer that stopped
reading could prevent deadlines and close from acquiring that mutex. Writes
now belong to one dedicated worker. Short state transitions serialize queue
admission, document versions, response routing, and closing; they never wait
for pipe IO. In particular, a server request only queues its reply, so it cannot
block the receiver on stdin backpressure.

The queue has configurable message and UTF-8 payload-byte limits. Pending
requests have a separate limit. Defaults are 128 queued messages, 8 MiB of
queued payload, 128 pending requests, and a 16 MiB inbound body. Headers are
limited to 8192 bytes; malformed lengths, duplicate Content-Length, invalid
UTF-8, invalid JSON-RPC envelopes, and ambiguous result/error responses fail
the transport. Stderr retains its last 64 KiB. These are explicit experiment
defaults, not a supported capacity promise.

A request has one monotonic deadline covering encoding, queueing, writing, and
waiting for its reply. Notification traffic does not extend it. Cancellation
uses an optional caller-owned `Std.CancellationToken`, rather than an arbitrary
callback that could itself block deadline checking. Pre-cancelled requests and
expired deadlines fail before enqueueing. A cancelled queued request is skipped;
late replies to removed request IDs cannot answer another operation. If a
request is interrupted during its active write, the transport is retired: a
partially written frame must never be followed by a new frame. A watchdog also
retires stalled notification/server-reply writes. Retirement wakes waiters and
sends SIGTERM; scoped cleanup performs the remaining escalation and reaping.
These are application deadlines, subject to runtime scheduling and encoding
costs, rather than hard real-time bounds.

## Document and profile API

`Client.openDocument` returns a `Document` handle containing its owning session,
URI, and version. `Document.change` returns a new handle; `Document.close`
invalidates it. Versions increase across every admitted open/edit in a session,
including URI close/reopen. Lifecycle notifications and state changes enter
the writer queue together; failed queue admission leaves document state intact.

Document requests use `Document.request`/`Document.call`, with matching
`textDocument.uri` and, when provided, matching `textDocument.version`. The
handle is checked at admission and at response delivery. Edits and close/reopen
therefore reject in-flight obsolete results, even if the peer replies later.
This establishes a delivery boundary; callers must still associate stored
results with the handle's version after the call returns. A handle selects its
own client and cannot be presented as an admission token to another session.

`Document.diagnostics` rejects stale handles. Versioned pushes for another
version are discarded, and a new accepted push replaces the entire set.
Unversioned pushes remain explicitly unversioned: neither a handle nor a
readiness hook upgrades them into evidence of current-version processing.

`Client.request`/`Client.call` serve workspace/session operations and reject
parameters with a `textDocument` field. Profiles must use document handles for
document extensions as well; the generic transport cannot infer document
ownership from arbitrary extension payloads. The profile diagnostic hook now
takes a `Document`, replacing the previous client/URI pair. It still owns
language-specific readiness and diagnostic coverage, not the core.

## Ownership and shutdown

Closing admission is atomic. It rejects new public work and invalidates
existing queries immediately. One caller owns cleanup; concurrent and repeated
callers receive the same `CloseReport`. Cleanup attempts didClose, shutdown,
and exit, then waits for the IO workers and the child. It sends SIGTERM and,
on Unix, invokes `kill -KILL -- -<owned-process-group>` directly without a shell
when graceful termination does not complete. Spawn creates the owned process
group with `setsid`.

The leader is not reaped while inherited stdio may still be open, keeping its
PID reserved until group escalation is complete. This also handles a leader
that exits while a descendant ignores SIGTERM and retains the pipes. Success
requires the leader to be reaped and the receiver, writer, watchdog, and stderr
workers all to have stopped. Incomplete cleanup is reported explicitly;
repeated close does not conceal or retry that report.

Cancellation never sends process signals from the caller's task. It delegates
retirement to the tracked watchdog, which yields ownership to close and must
finish before the child is reaped. Failed writes clear their active-frame
marker. The stronger blocked-pipe test exposed both this bookkeeping gap and
the need to account for delayed signal senders explicitly; cleanup must not
leave a task capable of signalling a subsequently reused PID.

`Client.withSession` closes on both success and error. If analysis and cleanup
both fail, the action's original error is included alongside the cleanup
failure. The analyzer now uses this scope. Initialization failures also include
incomplete-cleanup information rather than discarding it. Initialize supplies
the real client process ID.

## Validation and remaining release decisions

Maintainer evidence is recorded under
`_out/verso-lsp-design/parley-lifecycle/`, including exact source copies and
their digest, a clean batch build, protocol results, offline sites, and browser
checks. `tests/lsp/run_spike.py --documents` reproduces the protocol and document
checks; the browser command is in `tests/lsp/README.md`.

The final experiment source digest is
`08d6d66d41e5f18700b06e4f37af80bf995dde372bdeafbc407ec67ee5924c2f`.
The clean targeted build and complete `lake test` suite passed. The recorded
mock run returned from the query queued behind a blocked write in 120 ms for a
120 ms budget, from an interrupted active write in 502 ms for a 500 ms budget,
from the chatty request in 100 ms for a 100 ms budget, and from concurrent
SIGTERM-resistant cleanup in 1008 ms. The active-write test also asserts that
the interrupted session rejects new work, so encoding cannot exhaust its
budget before the write and accidentally satisfy the test. These are
observations from this run, not timing guarantees.

The mock tests cover blocked writes, cancellation/deadlines, capacity rejection,
stale results across edits and reopen, arbitrary server error codes, malformed
and partial input, concurrent/repeated close, SIGTERM resistance, and inherited
stdio. Real Rust and Rocq exercise the revised handles and profile hooks. The
independent core package still has no package dependencies; offline plain Verso
and Blueprint output retain the same semantic comparison and browser checks.

Before publishing an independent package:

- Set the supported platform contract. This batch validates Linux. The Unix
  escalation path needs the standard external `kill` utility at runtime, despite
  the library's dependency-free Lean build. Windows/macOS cleanup is unvalidated.
  Detached descendants that leave the owned process group are outside this
  ownership contract. Failure to terminate is reported, not hidden.
- Decide package/repository ownership and Lean release policy. Keep the core
  independent of Verso and keep the Verso bridge a separate library. No SubVerso
  fork has been required by either the document or lifecycle work.

Session pooling, persistent caches, external-input fingerprints, a high-level
existing-file/excerpt interface, and VBP node/proof-status admission remain
separate design work. This batch does not add those product contracts.
