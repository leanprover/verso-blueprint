/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.BrowserAsset
import VersoBlueprint.Commands.Common

namespace Informal.Slides.ClassicPreviewAdapter

/-!
Classic-script adapters for slide output.

Regular Manual pages load the ESM page runtime directly. This module quarantines
the remaining ESM-to-classic conversion needed by the current Slides asset
pipeline.
-/

private def previewGraphCoreModuleMjs : String := include_str "../blueprint-graph-core.mjs"

private def previewGraphCoreJs : String :=
  Informal.BrowserAsset.esmModuleToClassicScript previewGraphCoreModuleMjs
    "installGraphCoreGlobal(globalScope);"

private def previewCoreModuleMjs : String := include_str "../blueprint-preview-core.mjs"

private def previewCoreClassicPrelude : String := r##"
const graphDataUrl = function (filename, baseUrl) {
  const namespace =
    globalScope &&
    globalScope.VersoBlueprint &&
    typeof globalScope.VersoBlueprint.__private === "object"
      ? globalScope.VersoBlueprint.__private
      : {};
  const core = namespace.graphCore;
  if (core && typeof core.dataUrl === "function") {
    return core.dataUrl(filename, baseUrl);
  }
  const safeFilename = String(filename || "").trim();
  return safeFilename ? "-verso-data/" + safeFilename : "-verso-data/";
};
"##

private def previewCoreJs : String :=
  Informal.BrowserAsset.esmModuleToClassicScriptWithPrelude previewCoreModuleMjs
    previewCoreClassicPrelude
    "installPreviewCoreGlobal(globalScope);"

private def previewRuntimeBaseModuleMjs : String :=
  include_str "../Commands/preview-runtime-base.mjs"

private def previewRuntimeDataModuleMjs : String :=
  include_str "../Commands/preview-runtime-data.mjs"

private def previewRuntimeDataClassicPrelude : String := r##"
const previewRuntimeDataGlobal = typeof globalThis !== "undefined" ? globalThis : window;

const previewRuntimePrivateNamespace =
  previewRuntimeDataGlobal &&
  previewRuntimeDataGlobal.VersoBlueprint &&
  typeof previewRuntimeDataGlobal.VersoBlueprint.__private === "object"
    ? previewRuntimeDataGlobal.VersoBlueprint.__private
    : {};

function callRuntimePreviewCore(name, args, fallback) {
  const core = previewRuntimePrivateNamespace.previewCore || null;
  const method = core && core[name];
  if (typeof method === "function") {
    return method.apply(core, args);
  }
  if (typeof fallback === "function") {
    return fallback();
  }
  return fallback;
}

function callRuntimeGraphCore(name, args, fallback) {
  const core = previewRuntimePrivateNamespace.graphCore || null;
  const method = core && core[name];
  if (typeof method === "function") {
    return method.apply(core, args);
  }
  if (typeof fallback === "function") {
    return fallback();
  }
  return fallback;
}

const coreDataUrl = function (filename, baseUrl) {
  return callRuntimePreviewCore("dataUrl", [filename, baseUrl], function () {
    const safeFilename = String(filename || "").trim();
    return safeFilename ? "-verso-data/" + safeFilename : "-verso-data/";
  });
};

const coreManifestUrl = function (baseUrl) {
  return callRuntimePreviewCore("manifestUrl", [baseUrl], function () {
    return coreDataUrl("blueprint-manifest.json", baseUrl);
  });
};

const coreHtmlCacheUrl = function (baseUrl) {
  return callRuntimePreviewCore("htmlCacheUrl", [baseUrl], function () {
    return coreDataUrl("blueprint-html-cache.json", baseUrl);
  });
};

const coreGraphApiModuleUrl = function (baseUrl) {
  return callRuntimePreviewCore("graphApiModuleUrl", [baseUrl], function () {
    return coreDataUrl("api/graph.mjs", baseUrl);
  });
};

const corePreviewApiModuleUrl = function (baseUrl) {
  return callRuntimePreviewCore("previewApiModuleUrl", [baseUrl], function () {
    return coreDataUrl("api/preview.mjs", baseUrl);
  });
};

const corePreviewKey = function (label, facet) {
  return callRuntimePreviewCore("previewKey", [label, facet], "");
};

const coreStatementPreviewKey = function (label) {
  return callRuntimePreviewCore("statementPreviewKey", [label], function () {
    return corePreviewKey(label, "statement");
  });
};

const coreGraphsFromManifest = function (manifest) {
  return callRuntimeGraphCore("graphsFromManifest", [manifest], []);
};

const coreGetGraphData = function (root) {
  return callRuntimeGraphCore("getGraphData", [root], null);
};

const coreGetGraphVariants = function (root) {
  return callRuntimeGraphCore("getGraphVariants", [root], []);
};

const coreLoadManifestGraphs = function (url, options) {
  return callRuntimeGraphCore("loadManifestGraphs", [url, options], function () {
    return Promise.reject(new Error("Blueprint graph API unavailable"));
  });
};

const coreLoadGraphs = function (options) {
  return callRuntimeGraphCore("loadGraphs", [options], function () {
    return coreLoadManifestGraphs(coreManifestUrl(), options);
  });
};
"##

private def previewRuntimeRenderModuleMjs : String :=
  include_str "../Commands/preview-runtime-render.mjs"

private def previewRuntimeHydrationModuleMjs : String :=
  include_str "../Commands/preview-runtime-hydration.mjs"

private def previewRuntimeLifecycleModuleMjs : String :=
  include_str "../Commands/preview-runtime-lifecycle.mjs"

private def previewRuntimeSurfaceModuleMjs : String :=
  include_str "../Commands/preview-runtime-surface.mjs"

private def previewRuntimeTemplateModuleMjs : String :=
  include_str "../Commands/preview-runtime-template.mjs"

private def previewRuntimeApiModuleMjs : String :=
  include_str "../Commands/preview-runtime-api.mjs"

private def previewRuntimeFragments : List String :=
  [ Informal.BrowserAsset.esmModuleToClassicFragment previewRuntimeBaseModuleMjs,
    Informal.BrowserAsset.esmModuleToClassicFragmentWithPrelude
      previewRuntimeDataModuleMjs
      previewRuntimeDataClassicPrelude,
    Informal.BrowserAsset.esmModuleToClassicFragment previewRuntimeRenderModuleMjs,
    Informal.BrowserAsset.esmModuleToClassicFragment previewRuntimeHydrationModuleMjs,
    Informal.BrowserAsset.esmModuleToClassicFragment previewRuntimeLifecycleModuleMjs,
    Informal.BrowserAsset.esmModuleToClassicFragment previewRuntimeSurfaceModuleMjs,
    Informal.BrowserAsset.esmModuleToClassicFragment previewRuntimeTemplateModuleMjs,
    Informal.BrowserAsset.esmModuleToClassicFragment previewRuntimeApiModuleMjs ++
      "\ninstallPreviewRuntimeApi();" ]

private def previewRuntimeJs : String :=
  "(function () {\n" ++
  "  if (window.VersoBlueprint && window.VersoBlueprint.render) return;\n\n" ++
  String.intercalate "\n" previewRuntimeFragments ++ "\n" ++
  "})();"

def previewClientRuntimeJs : String :=
  previewGraphCoreJs ++ "\n" ++ previewCoreJs ++ "\n" ++ previewRuntimeJs

private def previewClientReadyModuleMjs : String :=
  include_str "../Commands/preview-ready.mjs"

def previewClientReadyJs : String :=
  Informal.BrowserAsset.esmModuleToClassicScript previewClientReadyModuleMjs
    "installPreviewClientReady(globalScope);"

def withPreviewClientReadyJs (js : String) : String :=
  previewClientReadyJs ++ "\n" ++ js

private def inlinePreviewModuleMjs : String :=
  include_str "../Commands/inline-preview.mjs"

def inlinePreviewJs : String :=
  withPreviewClientReadyJs <|
    Informal.BrowserAsset.esmModuleToClassicScript inlinePreviewModuleMjs r##"
window.VersoBlueprint.onRenderReady(function (previewUtils) {
  startInlinePreview(previewUtils);
});
"##

private def relationPanelModuleMjs : String :=
  include_str "../Informal/Block/relation-panel.mjs"

def relationPanelJs : String :=
  withPreviewClientReadyJs <|
    Informal.BrowserAsset.esmModuleToClassicScript relationPanelModuleMjs r##"
window.VersoBlueprint.onRenderReady(function (previewUtils) {
  startRelationPanels(previewUtils);
});
"##

private def graphRuntimeCoreModuleMjs : String :=
  include_str "../Commands/graph-runtime-core.mjs"

private def graphRuntimeCoreJs : String :=
  Informal.BrowserAsset.esmModuleToClassicScript graphRuntimeCoreModuleMjs r##"
const namespace =
  globalScope.VersoBlueprint && typeof globalScope.VersoBlueprint === "object"
    ? globalScope.VersoBlueprint
    : {};
const privateNamespace =
  namespace.__private && typeof namespace.__private === "object"
    ? namespace.__private
    : {};
namespace.__private = privateNamespace;
globalScope.VersoBlueprint = namespace;
const existingCore =
  privateNamespace.graphRuntimeCore &&
    typeof privateNamespace.graphRuntimeCore === "object"
    ? privateNamespace.graphRuntimeCore
    : {};
Object.assign(existingCore, graphRuntimeCore);
privateNamespace.graphRuntimeCore = existingCore;
"##

private def graphRuntimeModuleMjs : String :=
  include_str "../Commands/graph.mjs"

private def graphRuntimeClassicPrelude : String := r##"
const privateNamespace =
  globalScope.VersoBlueprint &&
  typeof globalScope.VersoBlueprint.__private === "object"
    ? globalScope.VersoBlueprint.__private
    : {};
const graphRuntimeCoreModule =
  privateNamespace.graphRuntimeCore &&
    typeof privateNamespace.graphRuntimeCore === "object"
    ? privateNamespace.graphRuntimeCore
    : {};
const graphCoreModule =
  privateNamespace.graphCore &&
    typeof privateNamespace.graphCore === "object"
    ? privateNamespace.graphCore
    : {};
const coreGetGraphData =
  typeof graphCoreModule.getGraphData === "function"
    ? graphCoreModule.getGraphData
    : function () { return null; };
const coreGetGraphVariants =
  typeof graphCoreModule.getGraphVariants === "function"
    ? graphCoreModule.getGraphVariants
    : function () { return []; };
"##

private def graphRuntimeClientJs : String :=
  Informal.BrowserAsset.esmModuleToClassicScriptWithPrelude
    graphRuntimeModuleMjs
    graphRuntimeClassicPrelude
    r##"
window.VersoBlueprint.onRenderReady(function (previewUtils) {
  startGraphRuntime(previewUtils);
});
"##

def graphRuntimeJs : String :=
  withPreviewClientReadyJs (graphRuntimeCoreJs ++ "\n" ++ graphRuntimeClientJs)

private def slideNodeHydrationModuleMjs : String := include_str "blueprint-slides.mjs"

def slideNodeHydrationJs : String :=
  Informal.BrowserAsset.esmModuleToClassicScript slideNodeHydrationModuleMjs
    "installBlueprintSlides();"

def previewRuntimeAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  { js := [previewClientRuntimeJs] }

def inlinePreviewAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  { js := previewRuntimeAssetBundle.js ++ [inlinePreviewJs] }

end Informal.Slides.ClassicPreviewAdapter
