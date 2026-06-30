/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Informal.ExternalMarkupRender

namespace Informal.PreviewManifest

open Verso.Genre Manual

def parseRenderConfigOptions (config : RenderConfig := {}) :
    List String → ReaderT ExtensionImpls IO RenderConfig
  | ("--output"::dir::more) => parseRenderConfigOptions { config with destination := dir } more
  | ("--depth"::n::more) => parseRenderConfigOptions { config with htmlDepth := n.toNat! } more

  | ("--with-tex"::more) => parseRenderConfigOptions { config with emitTeX := true } more
  | ("--without-tex"::more) => parseRenderConfigOptions { config with emitTeX := false } more

  | ("--with-html-single"::more) =>
      parseRenderConfigOptions { config with emitHtmlSingle := .immediately } more
  | ("--delay-html-single"::more) =>
    match Verso.CLI.requireFilename "--delay-html-single" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlSingle := .delay f } more'
    | .error e => throw (↑ e)
  | ("--resume-html-single"::more) =>
    match Verso.CLI.requireFilename "--resume-html-single" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlSingle := .resumeFrom f } more'
    | .error e => throw (↑ e)
  | ("--without-html-single"::more) =>
      parseRenderConfigOptions { config with emitHtmlSingle := .no } more

  | ("--with-html-multi"::more) =>
      parseRenderConfigOptions { config with emitHtmlMulti := .immediately } more
  | ("--delay-html-multi"::more) =>
    match Verso.CLI.requireFilename "--delay-html-multi" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlMulti := .delay f } more'
    | .error e => throw (↑ e)
  | ("--resume-html-multi"::more) =>
    match Verso.CLI.requireFilename "--resume-html-multi" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlMulti := .resumeFrom f } more'
    | .error e => throw (↑ e)
  | ("--without-html-multi"::more) =>
      parseRenderConfigOptions { config with emitHtmlMulti := .no } more

  | ("--with-word-count"::more) =>
    match Verso.CLI.requireFilename "--with-word-count" more with
    | .ok file more' _ => parseRenderConfigOptions { config with wordCount := some file } more'
    | .error e => throw (↑ e)
  | ("--without-word-count"::more) => parseRenderConfigOptions { config with wordCount := none } more
  | ("--draft"::more) => parseRenderConfigOptions { config with draft := true } more
  | ("--verbose"::more) => parseRenderConfigOptions { config with verbose := true } more
  | ("--remote-config"::more) =>
    match Verso.CLI.requireFilename "--remote-config" more with
    | .ok file more' _ => parseRenderConfigOptions { config with remoteConfigFile := some file } more'
    | .error e => throw (↑ e)
  | (other :: _) => throw (↑ s!"Unknown option {other}")
  | [] => pure config

def externalMarkupRenderFlag : String := "--external-markup-render"

private partial def parseExternalMarkupRenderOptions (config : Informal.ExternalMarkupRender.Config := {}) :
    List String → Except String (Informal.ExternalMarkupRender.Config × List String)
  | [] => .ok (config, [])
  | flag :: value :: more =>
      if flag == externalMarkupRenderFlag then
        match Informal.ExternalMarkupRender.Mode.parse? value with
        | some mode => parseExternalMarkupRenderOptions { config with mode } more
        | none =>
            .error s!"Unknown value for {externalMarkupRenderFlag}: {value}. Expected one of: {Informal.ExternalMarkupRender.Mode.cliValues}"
      else
        match parseExternalMarkupRenderOptions config (value :: more) with
        | .ok (config, options) => .ok (config, flag :: options)
        | .error err => .error err
  | [flag] =>
      if flag == externalMarkupRenderFlag then
        .error s!"Missing value for {externalMarkupRenderFlag}. Expected one of: {Informal.ExternalMarkupRender.Mode.cliValues}"
      else
        .ok (config, [flag])

def parseExternalMarkupRenderOptionsIO
    (config : Informal.ExternalMarkupRender.Config) (options : List String) :
    IO (Informal.ExternalMarkupRender.Config × List String) :=
  match parseExternalMarkupRenderOptions config options with
  | .ok parsed => pure parsed
  | .error err => throw <| IO.userError err

def dumpSchemaFlag : String := "--dump-schema"
def dumpManifestFlag : String := "--dump-manifest"
def dumpHtmlCacheFlag : String := "--dump-html-cache"
def helpFlag : String := "--help"

def helpText : String := String.intercalate "\n" [
  "Blueprint manifest/cache options:",
  s!"  {dumpSchemaFlag}       Print the semantic manifest JSON Schema and exit.",
  s!"  {dumpManifestFlag}     Print the generated semantic manifest JSON and exit.",
  s!"  {dumpHtmlCacheFlag}  Print the generated rendered-fragment cache JSON and exit.",
  s!"  {externalMarkupRenderFlag} <mode>  Render source-backed external fragments in the cache ({Informal.ExternalMarkupRender.Mode.cliValues}; default markdown, conservative Markdown HTML).",
  s!"  {helpFlag}              Show this help text and exit.",
  "",
  "Standard manual rendering options:",
  "  --output <dir>",
  "  --depth <n>",
  "  --with-tex | --without-tex",
  "  --with-html-single | --delay-html-single <file> | --resume-html-single <file> | --without-html-single",
  "  --with-html-multi | --delay-html-multi <file> | --resume-html-multi <file> | --without-html-multi",
  "  --with-word-count <file> | --without-word-count",
  "  --draft",
  "  --verbose",
  "  --remote-config <file>"
]

def stripFlag (flag : String) (args : List String) : List String :=
  args.filter (· != flag)

end Informal.PreviewManifest
