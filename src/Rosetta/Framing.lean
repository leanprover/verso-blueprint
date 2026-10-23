/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Data.Lsp.Communication
import Rosetta.Error

namespace Rosetta.Internal

/-- Bounded framing for an untrusted stdio peer. Reading runs on a dedicated
worker; a partial header/body is interrupted by terminating the owned process. -/
def readFrame (output : IO.FS.Stream) (maxBytes : Nat) : EIO ClientError String := do
  let mut header := ByteArray.empty
  repeat
    if header.size ≥ 8192 then throw <| ClientError.protocol "LSP header exceeds 8192 bytes"
    let byte ← output.read 1
    if byte.isEmpty then throw ClientError.disconnected
    header := header ++ byte
    if header.size ≥ 4 && header.extract (header.size - 4) header.size == "\r\n\r\n".toUTF8 then break
  let some headerText := String.fromUTF8? header | throw <| ClientError.protocol "invalid UTF-8 LSP header"
  let length? ← EIO.ofExcept <| (headerText.splitOn "\r\n" |>.foldlM
    (fun (length? : Option Nat) (line : String) => do
      if line.isEmpty then return length?
      let fields := line.splitOn ":"
      unless fields.length ≥ 2 do throw "invalid LSP header"
      if fields[0]!.toLower != "content-length" then return length?
      if length?.isSome then throw "duplicate Content-Length"
      let some length := fields[1]!.trimAscii.toString.toNat?
        | throw "invalid Content-Length"
      if fields.length != 2 || length > maxBytes then throw "LSP body exceeds configured limit"
      return some length) (none : Option Nat) : Except String (Option Nat)).mapError ClientError.protocol
  let some length := length? | throw <| ClientError.protocol "missing Content-Length"
  let mut body := ByteArray.empty
  while body.size < length do
    let chunk ← output.read (min 4096 (length - body.size)).toUSize
    if chunk.isEmpty then throw ClientError.disconnected
    body := body ++ chunk
  let some text := String.fromUTF8? body | throw <| ClientError.protocol "invalid UTF-8 LSP body"
  return text

end Rosetta.Internal
