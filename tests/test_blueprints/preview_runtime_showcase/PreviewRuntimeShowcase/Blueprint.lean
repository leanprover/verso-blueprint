import Verso
import VersoManual
import VersoBlueprint
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary
import PreviewRuntimeShowcase.Chapters.CodePanels
import PreviewRuntimeShowcase.Chapters.CorePreviews
import PreviewRuntimeShowcase.Chapters.GroupPreviews
import PreviewRuntimeShowcase.Chapters.InlineHoverPreviews
import PreviewRuntimeShowcase.Chapters.PreviewRelationships

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Preview Runtime Showcase" =>

This small in-repo Blueprint is dedicated to rendering and preview regressions.
It intentionally avoids pulling in a domain-specific proof corpus so browser and
generator checks can run against a focused, synthetic site.

{include 0 PreviewRuntimeShowcase.Chapters.CorePreviews}
{include 0 PreviewRuntimeShowcase.Chapters.CodePanels}
{include 0 PreviewRuntimeShowcase.Chapters.GroupPreviews}
{include 0 PreviewRuntimeShowcase.Chapters.PreviewRelationships}
{include 0 PreviewRuntimeShowcase.Chapters.InlineHoverPreviews}

{blueprint_graph (pack := true)}
{blueprint_summary}
