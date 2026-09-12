# Native preview RPC boundary

Setup, the embedded demo, and outstanding gates are documented in
[Native Blueprint preview](./NATIVE_PREVIEW_SESSION.md).

The scalar fixture (`NativePreview.lean`) verifies the native JSON boundary
against VIR's real Lean server fixture. The String fixture (`StringPreview.lean`
and `StringPreviewServer.lean`) exercises the complete retained renderer with
VBP-owned responses and deliberate error/cancellation cases. These are protocol
fixtures; the embedded fixture separately reads the open Blueprint document.

The client checks ordinary response scalars explicitly. A document crosses RPC
as `Preview.encode preview : String`, followed by one `Preview.decode` after the
request is accepted. React state retains the resulting Lean value through `JSL`;
there are no state JSON round trips or implicit wire/Lean ABI conversions.

Editor changes use the upstream notification hook. Cursor and document identity
are explicit inputs. Request effects use cancellation plus an independent
stale-result guard; control toggles do not request another document.

The campaigns reuse VIR's pinned internal real-server/browser test entry point.
A supported external-workspace harness and a published source/SDK pair remain
upstream integration work. No additional test framework is introduced here.
