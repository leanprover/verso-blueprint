module

public import VersoBlueprint
meta import VersoBlueprint
import ProjectTemplate.Chapters.Addition
import ProjectTemplate.Chapters.Collatz
import ProjectTemplate.Chapters.Multiplication

public section

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Starter Blueprint" =>

This small Blueprint tracks a few basic arithmetic facts on natural numbers,
then ends with a separate Collatz chapter that is intentionally unfinished. It
is intentionally small, so it can serve as a starting point for a new project.

{include 0 ProjectTemplate.Chapters.Addition}
{include 0 ProjectTemplate.Chapters.Multiplication}
{include 0 ProjectTemplate.Chapters.Collatz}

{blueprint_graph}
{blueprint_summary}
