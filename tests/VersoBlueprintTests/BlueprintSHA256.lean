/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Util.SHA256

/-! Known SHA-256 vectors, including UTF-8, padding boundaries and multiple
blocks. Expected digests were independently computed with Python's `hashlib`.
-/

namespace VersoBlueprintTests.BlueprintSHA256

private def ensure (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

#eval show IO Unit from do
  ensure (Informal.SHA256.digest ByteArray.empty ==
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    "SHA-256 empty vector"
  ensure (Informal.SHA256.text "abc" ==
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    "SHA-256 abc vector"
  ensure (Informal.SHA256.text "λ🐈" ==
    "b971a8b4a4603da87b83395e8ffd234ba7ae8aee7adb385bf7a2373b221d9ac9")
    "SHA-256 UTF-8 vector"
  ensure (Informal.SHA256.text
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" ==
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    "SHA-256 multi-block vector"
  for (size, expected) in #[
      (55, "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
      (56, "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
      (63, "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
      (64, "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
      (65, "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"),
      (1000, "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    ] do
    ensure (Informal.SHA256.digest ⟨Array.replicate size 97⟩ == expected)
      s!"SHA-256 padding/multi-block vector at {size} bytes"
  ensure (Informal.SHA256.tagged "blueprint-node-v1" #["node-A", "realization:lean"] ==
    "b32ccbf97dee13e28a217fb27fee638fb853d2dd9b592794c9e6490abf87afa9")
    "SHA-256 tagged known vector"
  ensure (Informal.SHA256.tagged "domain-a" #["ab", "c"] !=
      Informal.SHA256.tagged "domain-a" #["a", "bc"])
    "Tagged input must preserve part boundaries"
  ensure (Informal.SHA256.tagged "domain-a" #["same"] !=
      Informal.SHA256.tagged "domain-b" #["same"])
    "Tagged input must preserve its domain"

end VersoBlueprintTests.BlueprintSHA256
