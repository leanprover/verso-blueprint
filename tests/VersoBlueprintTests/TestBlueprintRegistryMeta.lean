/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

namespace Verso.VersoBlueprintTests.TestBlueprintRegistryMeta

structure CuratedTestBlueprintMeta where
  slug : String
  title : String
  category : String
  summary : String
  tags : Array String
  kind : String
deriving Lean.ToJson

def curatedTestBlueprintMetas : Array CuratedTestBlueprintMeta := #[
  {
    slug := "hover-link"
    title := "Hover Link Doc"
    category := "Preview"
    summary := "Inline reference and bibliography hover coverage."
    tags := #["hover", "inline", "citation"]
    kind := "curated_doc"
  },
  {
    slug := "hover-uses-dedup"
    title := "Hover Uses Dedup Doc"
    category := "Preview"
    summary := "Repeated uses-links against the same target without duplicate templates."
    tags := #["hover", "inline", "uses"]
    kind := "curated_doc"
  },
  {
    slug := "hover-cite-only"
    title := "Hover Cite Only Doc"
    category := "Preview"
    summary := "Bibliography-only inline hover coverage."
    tags := #["hover", "inline", "citation"]
    kind := "curated_doc"
  },
  {
    slug := "widget-preview"
    title := "Blueprint Widget Preview"
    category := "Preview"
    summary := "Widget-side TeX prelude and preview rendering checks."
    tags := #["preview", "widget", "tex"]
    kind := "curated_doc"
  },
  {
    slug := "rust-inline-preview"
    title := "Rust Attachment Showcase"
    category := "Code"
    summary := "Inline Rust attachment rendering with simple syntax coloring."
    tags := #["rust", "inline", "code"]
    kind := "curated_doc"
  },
  {
    slug := "metadata-panel"
    title := "Blueprint Metadata Panel"
    category := "Metadata"
    summary := "Owner, tags, effort, priority, and PR metadata rendering."
    tags := #["metadata", "summary"]
    kind := "curated_doc"
  },
  {
    slug := "direct-imported-duplicates"
    title := "Direct Imported Duplicates"
    category := "Imports"
    summary := "Duplicate imported node, group, and author diagnostics."
    tags := #["imports", "providers", "diagnostics"]
    kind := "curated_doc"
  },
  {
    slug := "transitive-imported-duplicates"
    title := "Transitive Imported Duplicates"
    category := "Imports"
    summary := "Duplicate imported diagnostics through a reexport chain."
    tags := #["imports", "providers", "diagnostics"]
    kind := "curated_doc"
  },
  {
    slug := "imported-preview-source"
    title := "Imported Preview Source"
    category := "Imports"
    summary := "Imported preview bodies and cross-module preview source coverage."
    tags := #["imports", "preview", "providers"]
    kind := "curated_doc"
  },
  {
    slug := "state-showcase"
    title := "Blueprint Graph State Showcase"
    category := "Graph"
    summary := "Complete graph-state matrix with graph and summary pages."
    tags := #["graph", "summary", "state"]
    kind := "curated_doc"
  },
  {
    slug := "external-summary-links"
    title := "External Summary Links"
    category := "Summary"
    summary := "Summary links for external Lean declarations."
    tags := #["summary", "external", "lean"]
    kind := "curated_doc"
  },
  {
    slug := "summary-blockers"
    title := "Summary Blockers"
    category := "Summary"
    summary := "Missing declarations and incomplete Lean declarations in summary views."
    tags := #["summary", "lean", "blockers"]
    kind := "curated_doc"
  },
  {
    slug := "summary-triage"
    title := "Summary Triage"
    category := "Summary"
    summary := "Summary rollups by owner, tags, parent, and triage metadata."
    tags := #["summary", "metadata", "triage"]
    kind := "curated_doc"
  },
  {
    slug := "preview-wiring"
    title := "Blueprint Preview Wiring"
    category := "Runtime"
    summary := "Core graph and summary preview runtime wiring."
    tags := #["preview", "runtime", "graph", "summary"]
    kind := "curated_doc"
  },
  {
    slug := "used-by-preview"
    title := "Blueprint Used-By Preview Wiring"
    category := "Relationships"
    summary := "Used-by chips and preview panel behavior."
    tags := #["relationships", "used-by", "preview"]
    kind := "curated_doc"
  },
  {
    slug := "used-by-single-preview"
    title := "Blueprint Used-By Single Preview Wiring"
    category := "Relationships"
    summary := "Single reverse-dependency used-by rendering."
    tags := #["relationships", "used-by"]
    kind := "curated_doc"
  },
  {
    slug := "lean-status-chip"
    title := "Blueprint Lean Status Chip Wiring"
    category := "Summary"
    summary := "Lean status chip rendering for proved, sorry, axiom, and absent code."
    tags := #["summary", "status", "lean"]
    kind := "curated_doc"
  },
  {
    slug := "lean-code-link-preview"
    title := "Blueprint Lean Code Link Preview Wiring"
    category := "Preview"
    summary := "Inline Lean declaration preview links inside the summary."
    tags := #["preview", "inline", "lean"]
    kind := "curated_doc"
  },
  {
    slug := "group-preview"
    title := "Blueprint Group Preview Wiring"
    category := "Relationships"
    summary := "Declared group chips and group preview panel interactions."
    tags := #["relationships", "group", "preview"]
    kind := "curated_doc"
  },
  {
    slug := "missing-group-preview"
    title := "Blueprint Missing Group Preview Wiring"
    category := "Relationships"
    summary := "Fallback behavior for undeclared groups."
    tags := #["relationships", "group", "fallback"]
    kind := "curated_doc"
  },
  {
    slug := "single-declared-group"
    title := "Blueprint Single Declared Group Wiring"
    category := "Relationships"
    summary := "Declared group with only one member."
    tags := #["relationships", "group"]
    kind := "curated_doc"
  }
]

def findCuratedTestBlueprintMeta? (slug : String) : Option CuratedTestBlueprintMeta :=
  curatedTestBlueprintMetas.find? (·.slug == slug)

end Verso.VersoBlueprintTests.TestBlueprintRegistryMeta
