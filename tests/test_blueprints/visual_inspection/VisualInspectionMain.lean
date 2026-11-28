import VersoManual
import VersoBlueprint.PreviewManifest
import VisualInspection.Blueprint

open Verso Doc
open Verso.Genre Manual

def main (args : List String) : IO UInt32 :=
  Informal.PreviewManifest.blueprintMainWithPreviewData
    (%doc VisualInspection.Blueprint)
    args
    (extensionImpls := by exact extension_impls%)
