import Verso
import VersoManual
import VersoBlueprint
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary
import VisualInspection.Chapters.BlockAnatomy
import VisualInspection.Chapters.StatusMatrix
import VisualInspection.Chapters.NarrowLayouts
import VisualInspection.Chapters.LargeGraph

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Visual Inspection" =>

This Blueprint exists to be looked at. Each chapter isolates one part of the
generated pages and opens with a short list of what to check, for a person
reviewing the site or an agent reviewing screenshots.

Its content is synthetic: the mathematics is trivial so that every page stays
focused on layout and status display. Generate it with
`python3 -m scripts.blueprint_test_blueprints generate-all visual_inspection`.

{include 0 VisualInspection.Chapters.BlockAnatomy}
{include 0 VisualInspection.Chapters.StatusMatrix}
{include 0 VisualInspection.Chapters.NarrowLayouts}
{include 0 VisualInspection.Chapters.LargeGraph}

{blueprint_graph}
{blueprint_summary}
