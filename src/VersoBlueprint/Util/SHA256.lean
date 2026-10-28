/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Init
import Lean.Data.Json
import Vir.Hash

/-! Small stable Blueprint-facing wrappers around the pinned pure Lean
SHA-256 implementation in `lean_vir`. The implementation follows FIPS 180-4;
this module makes no proof or validation claim about cryptographic security.
Consumers that rely on collision resistance assume SHA-256 remains collision
resistant. These functions do not authenticate data.
-/

namespace Informal.SHA256

open Lean

/-- Lowercase hexadecimal SHA-256 of the exact input bytes. -/
public def digest (bytes : ByteArray) : String :=
  Vir.sha256 bytes

/-- Lowercase hexadecimal SHA-256 of the string's UTF-8 bytes. -/
public def text (value : String) : String :=
  digest value.toUTF8

/-- Domain-separated digest of a sequence of strings.

The input is the compact JSON array `[domain, [part₁, ..., partₙ]]`. The nested
array and JSON string escaping keep both boundaries and the domain unambiguous;
this encoding is specific to this digest API, not a general Blueprint
serialization format.
-/
public def tagged (domain : String) (parts : Array String) : String :=
  let encoded := Json.arr #[Json.str domain, Json.arr (parts.map Json.str)]
  digest encoded.compress.toUTF8

end Informal.SHA256
