import { collectPreviewTemplates, escapeHtml, previewDebug, previewDebugLabel } from "./preview-runtime-base.mjs";
import { createBlueprintDataApi } from "./preview-runtime-data.mjs";
import { renderBlueprintNodeInto, renderBlueprintPreviewInto, renderCanonicalBlueprintPreviewInto, resolveBlueprintPreview, resolveCanonicalBlueprintPreview } from "./preview-runtime-render.mjs";
import { hydrateRenderedPreview, registerPreviewHydrator } from "./preview-runtime-hydration.mjs";
import { bindAnchoredPopover } from "./preview-runtime-lifecycle.mjs";
import { createPreviewPanel, createPreviewSurface, hidePreviewSurfaces, previewMessageHtml, renderPreviewIntoSurface, resolvePreviewHtml } from "./preview-runtime-surface.mjs";
import { bindTemplatePreviewDescriptors } from "./preview-runtime-template.mjs";

// API assembly and readiness synchronization.

function defaultTemplatePreviewRoot(options) {
  const opts = options && typeof options === "object" ? options : {};
  if (opts.root && typeof opts.root.querySelectorAll === "function") {
    return opts.root;
  }
  return typeof document !== "undefined" ? document : null;
}

function templatePreviewDescriptorBinder(options) {
  const opts = options && typeof options === "object" ? options : {};
  return typeof opts.templateBinder === "function"
    ? opts.templateBinder
    : bindTemplatePreviewDescriptors;
}

function bindInitialTemplatePreviewDescriptors(options) {
  const opts = options && typeof options === "object" ? options : {};
  if (opts.bindTemplatePreviews === false) return;
  const root = defaultTemplatePreviewRoot(opts);
  if (!root || typeof root.querySelectorAll !== "function") return;
  const bindTemplatePreviews = templatePreviewDescriptorBinder(opts);
  if (
    typeof document !== "undefined" &&
    root === document &&
    document.readyState === "loading"
  ) {
    document.addEventListener("DOMContentLoaded", function () {
      bindTemplatePreviews(root, opts);
    }, { once: true });
    return;
  }
  bindTemplatePreviews(root, opts);
}

function previewRuntimeRenderOptions(options) {
  const opts = options && typeof options === "object" ? options : {};
  const renderOptions = {};
  if ("dataApi" in opts) renderOptions.dataApi = opts.dataApi;
  if ("fetchJson" in opts) renderOptions.fetchJson = opts.fetchJson;
  if ("hydrate" in opts) renderOptions.hydrate = opts.hydrate;
  if ("renderMath" in opts) renderOptions.renderMath = opts.renderMath;
  if ("hydrators" in opts) renderOptions.hydrators = opts.hydrators;
  if ("inheritPageHydrators" in opts) {
    renderOptions.inheritPageHydrators = opts.inheritPageHydrators;
  }
  if ("templateBinder" in opts) renderOptions.templateBinder = opts.templateBinder;
  if ("fetchText" in opts) renderOptions.fetchText = opts.fetchText;
  if ("loadDocument" in opts) renderOptions.loadDocument = opts.loadDocument;
  if ("canonicalBaseUrl" in opts) renderOptions.canonicalBaseUrl = opts.canonicalBaseUrl;
  if ("canonicalPreviewDocuments" in opts) {
    renderOptions.canonicalPreviewDocuments = opts.canonicalPreviewDocuments;
  }
  if ("canonicalPreviewHtmlByKey" in opts) {
    renderOptions.canonicalPreviewHtmlByKey = opts.canonicalPreviewHtmlByKey;
  }
  return renderOptions;
}

function mergePreviewRenderOptions(defaults, options) {
  const opts = options && typeof options === "object" ? options : {};
  return Object.assign({}, defaults || {}, opts);
}

export function createPreviewRuntimeApi(options) {
  const opts = options && typeof options === "object" ? options : {};
  const dataApi = createBlueprintDataApi(opts);
  const runtimeOptions = Object.assign({}, opts, { dataApi: dataApi });

  const previewDataApi = {
    dataUrl: dataApi.dataUrl,
    manifestUrl: dataApi.manifestUrl,
    htmlCacheUrl: dataApi.htmlCacheUrl,
    loadManifest: function (options) { return dataApi.loadManifest(options); },
    readManifestStatus: dataApi.readManifestStatus,
    loadManifestEntry: function (key, options) { return dataApi.loadManifestEntry(key, options); },
    loadSourceDocuments: function (options) { return dataApi.loadSourceDocuments(options); },
    loadSourceDocument: function (id, options) { return dataApi.loadSourceDocument(id, options); },
    loadHtmlCache: function (options) { return dataApi.loadHtmlCache(options); },
    readHtmlCacheStatus: dataApi.readHtmlCacheStatus,
    loadHtmlCacheEntry: function (key, options) { return dataApi.loadHtmlCacheEntry(key, options); },
    dataApiModuleUrl: dataApi.dataApiModuleUrl,
    previewApiModuleUrl: dataApi.previewApiModuleUrl,
    graphApiModuleUrl: dataApi.graphApiModuleUrl,
    previewKey: dataApi.previewKey,
    statementPreviewKey: dataApi.statementPreviewKey,
    resolveLabel: function (label, options) { return dataApi.resolveLabel(label, options); },
    resolveDeclaration: function (declName, options) {
      return dataApi.resolveDeclaration(declName, options);
    },
    resolvePreview: function (previewKey, options) {
      return resolveBlueprintPreview(
        previewKey,
        mergePreviewRenderOptions({ dataApi: dataApi }, options)
      );
    },
    resolveCanonicalPreview: function (previewKey, options) {
      return resolveCanonicalBlueprintPreview(
        previewKey,
        mergePreviewRenderOptions({ dataApi: dataApi }, options)
      );
    }
  };

  const defaultRenderOptions = previewRuntimeRenderOptions(runtimeOptions);
  if (!(defaultRenderOptions.canonicalPreviewDocuments instanceof Map)) {
    defaultRenderOptions.canonicalPreviewDocuments = new Map();
  }
  if (!(defaultRenderOptions.canonicalPreviewHtmlByKey instanceof Map)) {
    defaultRenderOptions.canonicalPreviewHtmlByKey = new Map();
  }
  const previewRenderApi = {
    renderPreviewInto: function (target, previewKey, options) {
      return renderBlueprintPreviewInto(
        target,
        previewKey,
        mergePreviewRenderOptions(defaultRenderOptions, options)
      );
    },
    renderCanonicalPreviewInto: function (target, previewKey, options) {
      return renderCanonicalBlueprintPreviewInto(
        target,
        previewKey,
        mergePreviewRenderOptions(defaultRenderOptions, options)
      );
    },
    renderNode: function (target, request, options) {
      return renderBlueprintNodeInto(
        target,
        request,
        mergePreviewRenderOptions(defaultRenderOptions, options)
      );
    },
    resolveSourceMetadata: function (source, options) {
      return dataApi.resolveSourceMetadata(
        source,
        mergePreviewRenderOptions(defaultRenderOptions, options)
      );
    },
    hydrate: function (element, options) {
      return hydrateRenderedPreview(
        element,
        mergePreviewRenderOptions(defaultRenderOptions, options)
      );
    }
  };

  const previewTemplateHelpers = {
    collectPreviewTemplates: collectPreviewTemplates
  };

  const previewContentHelpers = {
    escapeHtml: escapeHtml,
    previewMessageHtml: previewMessageHtml,
    createPreviewPanel: createPreviewPanel,
    createPreviewSurface: createPreviewSurface,
    renderPreviewIntoSurface: renderPreviewIntoSurface,
    resolvePreviewHtml: resolvePreviewHtml
  };

  const previewLifecycleHelpers = {
    bindAnchoredPopover: bindAnchoredPopover,
    hidePreviewSurfaces: hidePreviewSurfaces,
  };

  const previewHydrationHelpers = {
    registerPreviewHydrator: registerPreviewHydrator,
    previewDebug: previewDebug,
    previewDebugLabel: previewDebugLabel
  };

  const stableCustomClientApi = {
    dataUrl: previewDataApi.dataUrl,
    manifestUrl: previewDataApi.manifestUrl,
    htmlCacheUrl: previewDataApi.htmlCacheUrl,
    loadManifest: previewDataApi.loadManifest,
    readManifestStatus: previewDataApi.readManifestStatus,
    loadManifestEntry: previewDataApi.loadManifestEntry,
    loadSourceDocuments: previewDataApi.loadSourceDocuments,
    loadSourceDocument: previewDataApi.loadSourceDocument,
    loadHtmlCache: previewDataApi.loadHtmlCache,
    readHtmlCacheStatus: previewDataApi.readHtmlCacheStatus,
    loadHtmlCacheEntry: previewDataApi.loadHtmlCacheEntry,
    dataApiModuleUrl: previewDataApi.dataApiModuleUrl,
    previewApiModuleUrl: previewDataApi.previewApiModuleUrl,
    graphApiModuleUrl: previewDataApi.graphApiModuleUrl,
    previewKey: previewDataApi.previewKey,
    statementPreviewKey: previewDataApi.statementPreviewKey,
    resolveLabel: previewDataApi.resolveLabel,
    resolveDeclaration: previewDataApi.resolveDeclaration,
    resolvePreview: previewDataApi.resolvePreview,
    renderPreviewInto: previewRenderApi.renderPreviewInto,
    resolveCanonicalPreview: previewDataApi.resolveCanonicalPreview,
    renderCanonicalPreviewInto: previewRenderApi.renderCanonicalPreviewInto,
    renderNode: previewRenderApi.renderNode,
    resolveSourceMetadata: previewRenderApi.resolveSourceMetadata,
    hydrate: previewRenderApi.hydrate
  };

  const bundledFeatureRenderHelpers = {
    collectPreviewTemplates: previewTemplateHelpers.collectPreviewTemplates,
    escapeHtml: previewContentHelpers.escapeHtml,
    createPreviewSurface: previewContentHelpers.createPreviewSurface,
    registerPreviewHydrator: previewHydrationHelpers.registerPreviewHydrator,
    previewDebug: previewHydrationHelpers.previewDebug,
    previewDebugLabel: previewHydrationHelpers.previewDebugLabel,
    previewMessageHtml: previewContentHelpers.previewMessageHtml,
    createPreviewPanel: previewContentHelpers.createPreviewPanel,
    renderPreviewIntoSurface: function (surface, previewKey, options) {
      return previewContentHelpers.renderPreviewIntoSurface(
        surface,
        previewKey,
        mergePreviewRenderOptions(defaultRenderOptions, options)
      );
    },
    resolvePreviewHtml: function (previewKey, options) {
      return previewContentHelpers.resolvePreviewHtml(
        previewKey,
        mergePreviewRenderOptions(defaultRenderOptions, options)
      );
    },
    bindAnchoredPopover: previewLifecycleHelpers.bindAnchoredPopover,
    hidePreviewSurfaces: previewLifecycleHelpers.hidePreviewSurfaces
  };

  const renderApi = Object.assign(
    {},
    stableCustomClientApi,
    bundledFeatureRenderHelpers
  );

  bindInitialTemplatePreviewDescriptors(runtimeOptions);

  return renderApi;
}

export const previewRuntimeApi = {
  createPreviewRuntimeApi
};

export default previewRuntimeApi;
