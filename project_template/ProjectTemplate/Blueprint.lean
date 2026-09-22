module

public import VersoBlueprint
meta import VersoBlueprint
public import ProjectTemplate.Chapters.Addition
public import ProjectTemplate.Chapters.Collatz
public import ProjectTemplate.Chapters.Multiplication
public import ProjectTemplate.Formalization.Addition

public section

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Starter Blueprint" =>

This small Blueprint tracks a few basic arithmetic facts on natural numbers,
then ends with a separate Collatz chapter that is intentionally unfinished. It
is intentionally small, so it can serve as a starting point for a new project.

{include 0 ProjectTemplate.Chapters.Addition}
{includeBlueprintModule 0 ProjectTemplate.Formalization.Addition (title := "Compiled Addition Results")}
{include 0 ProjectTemplate.Chapters.Multiplication}
{include 0 ProjectTemplate.Chapters.Collatz}

{blueprint_graph}
{blueprint_summary}
