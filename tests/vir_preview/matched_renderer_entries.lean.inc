-- Appended inside the frozen renderer test namespace in an isolated consumer.
-- Reuse `rich` above; only the test entry and extra coverage are new.
private def acceptanceDocument (after : Bool) : Document :=
  let title := if after then "After λ😀 <script>escaped</script>" else "Before λ😀 <script>escaped</script>"
  { rich with
    document := .mk #[.text title] title none (rich.document.content ++ #[
      .para #[.text "Paragraph with ", .bold #[.text "strong text"], .emph #[.text " emphasis"]],
      .code "<script>code stays text</script>",
      .ul #[.mk #[.para #[.text "unordered"]]],
      .ol 3 #[.mk #[.para #[.text "ordered"]]],
      .dl #[.mk #[.text "Term"] #[.para #[.text "Definition"]]],
      .blockquote #[.para #[.text "quoted"]],
      block `Consumer.unsupported .null #[.para #[.text "unsupported child"]]
    ]) #[] }

@[vir_export]
def encoded (after : Bool) : String := Document.encode (acceptanceDocument after)

@[vir_export]
def renderDocumentJson (source : String) : IO (Js Node) := do
  match Document.decode source with
  | .ok doc => Lean.Vir.Browser.DomM.run <| ReactM.run <|
      VersoBlueprint.Experimental.VirPreview.Renderer.render doc
  | .error message => throw (IO.userError message)

-- Native generation supplies both engines with the exact existing codec bytes.
def writeInputs : IO Unit := IO.println (Lean.toJson #[encoded false, encoded true]).compress
