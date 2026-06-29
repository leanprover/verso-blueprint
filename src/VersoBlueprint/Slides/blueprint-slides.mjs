// Blueprint slide-node hydration.

function defaultWindow() {
  return typeof window !== "undefined" ? window : null;
}

function ensurePreviewUtils(previewUtils) {
  if (!previewUtils || typeof previewUtils !== "object") {
    throw new Error("Blueprint slide hydration requires a preview renderer.");
  }
  if (typeof previewUtils.hydrate !== "function") {
    throw new Error("Blueprint slide hydration requires previewUtils.hydrate().");
  }
  return previewUtils;
}

export function currentSlideRuntime(globalScope = defaultWindow()) {
  const windowObj = globalScope && globalScope.window ? globalScope.window : globalScope;
  if (!windowObj) return {};
  const namespace =
    windowObj.VersoBlueprint && typeof windowObj.VersoBlueprint === "object"
      ? windowObj.VersoBlueprint
      : {};
  const slideRuntime =
    namespace.slides && typeof namespace.slides === "object"
      ? namespace.slides
      : {};
  namespace.slides = slideRuntime;
  windowObj.VersoBlueprint = namespace;
  return slideRuntime;
}

export function trimSlashes(text, side) {
  let value = String(text || "");
  if (side === "left" || side === "both") value = value.replace(/^\/+/, "");
  if (side === "right" || side === "both") value = value.replace(/\/+$/, "");
  return value;
}

export function readBlueprintBaseUrl(node, runtime = currentSlideRuntime()) {
  if (node instanceof Element) {
    const local = (node.getAttribute("data-bp-site-base") || "").trim();
    if (local) return local;
    const host = node.closest("[data-bp-site-base]");
    if (host instanceof Element) {
      const hostBase = (host.getAttribute("data-bp-site-base") || "").trim();
      if (hostBase) return hostBase;
    }
  }
  const runtimeBase =
    runtime && typeof runtime.blueprintBaseUrl === "string"
      ? runtime.blueprintBaseUrl
      : "";
  return runtimeBase.trim();
}

export function rememberBlueprintBaseUrl(node, runtime = currentSlideRuntime()) {
  const baseUrl = readBlueprintBaseUrl(node, runtime);
  if (baseUrl && runtime) runtime.blueprintBaseUrl = baseUrl;
  return baseUrl;
}

export function resolveBlueprintHref(href, baseUrl) {
  const raw = String(href || "").trim();
  if (!raw || raw.startsWith("#")) return raw;
  if (/^[a-z][a-z0-9+.-]*:/i.test(raw) || raw.startsWith("//")) return raw;
  const base = String(baseUrl || "").trim();
  if (!base) return raw;
  return trimSlashes(base, "right") + "/" + trimSlashes(raw, "left");
}

export function prepareBlueprintLinks(root, baseUrl) {
  if (!(root instanceof Element)) return;
  root.querySelectorAll("a[href]").forEach(function (link) {
    if (!(link instanceof HTMLAnchorElement)) return;
    const raw = (
      link.getAttribute("data-bp-slide-href") ||
      link.getAttribute("href") ||
      ""
    ).trim();
    if (!raw || raw.startsWith("#")) return;
    link.setAttribute("data-bp-slide-href", raw);
    link.href = resolveBlueprintHref(raw, baseUrl);
    link.target = "bp-slide-blueprint";
    link.rel = "noopener";
    link.setAttribute("data-bp-slide-link", "blueprint");
  });
}

export function hydrate(root, previewUtils, options = {}) {
  const preview = ensurePreviewUtils(previewUtils);
  const scope = root && typeof root.querySelectorAll === "function" ? root : document;
  const runtime = currentSlideRuntime(options.globalScope);
  scope.querySelectorAll(".bp_slide_node").forEach(function (node) {
    if (!(node instanceof Element)) return;
    const baseUrl = rememberBlueprintBaseUrl(node, runtime);
    prepareBlueprintLinks(node, baseUrl);
    preview.hydrate(node);
  });
  if (typeof preview.renderGraphs === "function") {
    preview.renderGraphs(scope, { refresh: true });
  }
}

export function registerPreviewHydrator(previewUtils) {
  const preview = ensurePreviewUtils(previewUtils);
  preview.registerPreviewHydrator("slideBlueprintLinks", function (root) {
    if (!(root instanceof Element)) return;
    prepareBlueprintLinks(root, readBlueprintBaseUrl(root));
  });
}

export function start(previewUtils, options = {}) {
  const preview = ensurePreviewUtils(previewUtils);
  const runtime = currentSlideRuntime(options.globalScope);
  runtime.hydrate = function (root) {
    hydrate(root, preview, options);
    return Promise.resolve();
  };
  if (runtime.started) {
    hydrate(document, preview, options);
    return runtime;
  }
  runtime.started = true;

  registerPreviewHydrator(preview);
  const hydrateRoot = function (root) {
    hydrate(root || document, preview, options);
  };
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      hydrateRoot(document);
    }, { once: true });
  } else {
    hydrateRoot(document);
  }
  if (window.Reveal && typeof window.Reveal.on === "function") {
    window.Reveal.on("slidechanged", function (event) {
      preview.hidePreviewSurfaces(document);
      hydrateRoot(event.currentSlide || document);
    });
    window.Reveal.on("ready", function (event) {
      hydrateRoot(event.currentSlide || document);
    });
  }
  return runtime;
}

export function installBlueprintSlides(previewUtils, options = {}) {
  return start(previewUtils, options);
}

export const blueprintSlidesRuntime = {
  currentSlideRuntime,
  trimSlashes,
  readBlueprintBaseUrl,
  rememberBlueprintBaseUrl,
  resolveBlueprintHref,
  prepareBlueprintLinks,
  hydrate,
  registerPreviewHydrator,
  start,
  installBlueprintSlides
};

export default blueprintSlidesRuntime;
