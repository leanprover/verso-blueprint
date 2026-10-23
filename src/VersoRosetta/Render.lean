/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Rosetta.Document
import Verso.Doc.Html
import Verso.Doc.TeX

namespace VersoRosetta
open Lean Verso Verso.Output Rosetta

def requestAnchor (key : String) : String := s!"verso-rosetta-{hash key}"

def css : String := "
.hl.lsp { white-space: pre; font-family: monospace; }
.lsp-panel { margin-block: 1rem; min-width: 0; max-width: 100%; width: 100%; }
.lsp-panel pre { overflow-x: auto; padding: .8rem; background: var(--code-bg, #f3f4f6); }
.lsp-keyword { color: #7c3aed; font-weight: 600; }
.lsp-type { color: #0369a1; }
.lsp-function { color: #9a3412; }
.lsp-literal { color: #166534; }
.lsp-comment { color: #64748b; }
.lsp-error { text-decoration: underline wavy #b91c1c; text-underline-offset: .2em; }
.lsp-status { font-size: .85em; color: var(--text-muted, #6b7280); }
.lsp-diagnostics { border-left: .2em solid #b91c1c; padding-left: 1.5rem; }
.lsp-hover-content { white-space: pre-wrap; max-width: 40rem; font-family: monospace; }
.tippy-box[data-theme~='verso-rosetta'] { background: #fff; color: #111827; border: 1px solid #9ca3af; }
"

/-- Reuse Verso's generated hover table and Tippy assets, with neutral selectors.
Verso's current Lean binder selects `.hl.lean` and cannot bind these spans. -/
def hoverJs : String := "
window.addEventListener('load', async () => {
  const nodes = document.querySelectorAll('.hl.lsp [data-verso-hover]');
  if (!nodes.length) return;
  try {
    const response = await fetch('-verso-docs.json');
    if (!response.ok) throw new Error('hover table unavailable');
    const docs = await response.json();
    for (const node of nodes) {
      const html = docs[node.dataset.versoHover];
      if (typeof html !== 'string') continue;
      tippy(node, { content: html, allowHTML: true, interactive: true,
        theme: 'verso-rosetta', trigger: 'mouseenter focus', maxWidth: 'none' });
    }
  } catch (error) { console.error('Verso Rosetta hovers:', error); }
});
"

private def tokenClass (kind : String) : String :=
  if #["keyword", "modifier"].contains kind then "lsp-keyword"
  else if #["type", "typeParameter", "struct", "class", "interface", "enum"].contains kind then "lsp-type"
  else if #["function", "method"].contains kind then "lsp-function"
  else if #["string", "number", "regexp"].contains kind then "lsp-literal"
  else if kind == "comment" then "lsp-comment" else "lsp-token"

private def covers (text : String) (range : Lsp.Range) (start stop : Nat) : Bool :=
  match byteRange? text range with
  | some (left, right) => left ≤ start && stop ≤ right
  | none => false

private def hoverContent (query : QuerySnapshot) : Html :=
  let content := match query.hover with
    | .ok (some hover) => Html.tag "pre" #[("class", "lsp-hover-content")] (.text true hover.text)
    | .ok none | .unsupported => .empty
    | .failed message => Html.tag "p" #[] (.text true s!"Hover unavailable: {message}")
  let definitions := match query.definitions with
    | .ok targets => Html.tag "p" #[] <| .text true <|
        if targets.isEmpty then "Unresolved reference"
        else if targets.size == 1 then "Definition found"
        else s!"Multiple definition targets: {targets.size}"
    | .unsupported => Html.tag "p" #[] (.text true "Definition lookup unsupported")
    | .failed message => Html.tag "p" #[] (.text true s!"Definition lookup failed: {message}")
  content ++ definitions

/-- Render source from ranged overlays without encoding foreign identifiers as
Lean constants. Hover HTML is escaped before entering Verso's shared table. -/
def sourceHtml {g : Doc.Genre} (request : Request) (snapshot? : Option RequestSnapshot) :
    Code.HighlightHtmlM g Html := do
  let mut boundaries := #[0, request.text.utf8ByteSize]
  let tokens := snapshot?.map (fun snapshot => match snapshot.tokens with
    | .ok tokens => tokens | _ => #[]) |>.getD #[]
  let queries := snapshot?.map (·.queries) |>.getD #[]
  let diagnostics := snapshot?.map (·.diagnostics) |>.getD #[]
  let ranges := tokens.map (·.range) ++ queries.map (·.range) ++ diagnostics.map (·.diagnostic.range)
  for range in ranges do
    if let some (start, stop) := byteRange? request.text range then
      boundaries := boundaries.push start |>.push stop
  let points := (boundaries.qsort (· < ·)).foldl (fun out item =>
    if out.back? == some item then out else out.push item) (#[] : Array Nat)
  let mut out := Html.empty
  for index in [:points.size - 1] do
    let start := points[index]!
    let stop := points[index + 1]!
    let text := String.Pos.Raw.extract request.text ⟨start⟩ ⟨stop⟩
    let style := (tokens.find? (fun token => covers request.text token.range start stop)).map
      (fun token => tokenClass token.tokenType) |>.getD "lsp-token"
    let error := diagnostics.any fun diagnostic =>
      diagnostic.diagnostic.severity? == some .error && covers request.text diagnostic.diagnostic.range start stop
    let mut attrs := #[("class", style ++ if error then " lsp-error" else "")]
    let query? := queries.find? (fun query => covers request.text query.range start stop)
    if let some query := query? then
      let hoverId ← Code.addHover (g := g) (hoverContent query)
      attrs := attrs ++ #[("data-verso-hover", toString hoverId), ("tabindex", "0")]
    let span := Html.tag "span" attrs (.text true text)
    let localTarget? := query?.bind fun query => match query.definitions with
      | .ok targets => if targets.size == 1 && query.localTargets.size == 1 then query.localTargets[0]? else none
      | _ => none
    let span := match localTarget? with
      | some target => Html.tag "a" #[("href", "#" ++ requestAnchor target)] span
      | none => span
    out := out ++ span
  return out

def diagnosticsHtml (snapshot : RequestSnapshot) : Html :=
  if snapshot.diagnostics.isEmpty then .empty else
    Html.tag "ul" #[("class", "lsp-diagnostics")] <| .seq <| snapshot.diagnostics.map fun diagnostic =>
      let origin := diagnostic.authored[0]?
      let whereText := origin.map (fun location => s!" (source line {location.range.start.line + 1})") |>.getD ""
      Html.tag "li" #[] (.text true (diagnostic.diagnostic.message ++ whereText))

def codeHtml {g : Doc.Genre} (request : Request) (snapshot? : Option RequestSnapshot) :
    Code.HighlightHtmlM g Html := do
  let status := match snapshot? with
    | none => "Not analyzed"
    | some snapshot =>
      let highlighting := match snapshot.tokens with
        | .ok _ => ""
        | .unsupported => " · highlighting unsupported"
        | .failed _ => " · highlighting failed"
      s!"Analysis recorded · {snapshot.diagnostics.size} diagnostics{highlighting}"
  return Html.tag "section" #[("class", "lsp-panel"), ("id", requestAnchor request.key)] <| .seq #[
    Html.tag "p" #[("class", "lsp-status")] (.text true status),
    Html.tag "pre" #[] <| Html.tag "code" #[("class", "hl lsp")] (← sourceHtml request snapshot?),
    snapshot?.map diagnosticsHtml |>.getD .empty]

def referenceHtml {g : Doc.Genre} (request : Request) (snapshot? : Option RequestSnapshot) :
    Code.HighlightHtmlM g Html := do
  return Html.tag "code" #[("class", "hl lsp lsp-reference"), ("id", requestAnchor request.key)]
    (← sourceHtml request snapshot?)

end VersoRosetta
