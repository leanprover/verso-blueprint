  // Runtime-local registries. Keep these private and expose behavior through
  // the render API instead of growing new window globals.
  const localPreviewHydrators = new Map();
  export const previewHydrators = localPreviewHydrators;
  let bindTemplatePreviewDescriptorsImpl = function (_root) { return []; };

  function activePreviewHydrators() {
    return localPreviewHydrators;
  }

  // Hydration extension points and math rendering.

  export function setTemplatePreviewDescriptorBinder(fn) {
    bindTemplatePreviewDescriptorsImpl = typeof fn === "function"
      ? fn
      : function (_root) { return []; };
  }

  function isHydratableRoot(root) {
    const isElement =
      typeof Element !== "undefined" && root instanceof Element;
    const isDocument =
      typeof Document !== "undefined" && root instanceof Document;
    return isElement || isDocument;
  }

  function normalizeHydratorEntry(name, value) {
    if (typeof value === "function") {
      return {
        name: typeof name === "string" ? name : "",
        fn: value
      };
    }
    if (!value || typeof value !== "object") return null;
    if (typeof value.hydrate === "function") {
      return {
        name: typeof value.name === "string" ? value.name : (typeof name === "string" ? name : ""),
        fn: value.hydrate
      };
    }
    if (typeof value.fn === "function") {
      return {
        name: typeof value.name === "string" ? value.name : (typeof name === "string" ? name : ""),
        fn: value.fn
      };
    }
    return null;
  }

  export function normalizePreviewHydrators(hydrators) {
    if (!hydrators) return [];
    if (typeof hydrators === "function") {
      return [{ name: "", fn: hydrators }];
    }
    if (hydrators instanceof Map) {
      return Array.from(hydrators.entries()).flatMap(function (entry) {
        const normalized = normalizeHydratorEntry(String(entry[0] || ""), entry[1]);
        return normalized ? [normalized] : [];
      });
    }
    if (Array.isArray(hydrators)) {
      return hydrators.flatMap(function (entry, index) {
        const normalized = normalizeHydratorEntry(String(index), entry);
        return normalized ? [normalized] : [];
      });
    }
    if (typeof hydrators === "object") {
      return Object.entries(hydrators).flatMap(function (entry) {
        const normalized = normalizeHydratorEntry(entry[0], entry[1]);
        return normalized ? [normalized] : [];
      });
    }
    return [];
  }

  function runPreviewHydratorEntry(root, entry, source) {
    if (!entry || typeof entry.fn !== "function") return;
    try {
      entry.fn(root, {
        name: entry.name || "",
        source: source || ""
      });
    } catch (_err) {}
  }

  export function hydrateRenderedPreview(root, options) {
    const opts = options && typeof options === "object" ? options : {};
    if (!isHydratableRoot(root)) return false;
    if (opts.hydrate !== false) {
      const bindTemplatePreviewDescriptors =
        typeof opts.templateBinder === "function"
          ? opts.templateBinder
          : bindTemplatePreviewDescriptorsImpl;
      bindTemplatePreviewDescriptors(root, opts);
      runPreviewHydrators(root, opts);
    }
    if (opts.renderMath !== false) {
      renderBlueprintMath(root);
    }
    return true;
  }

  export function renderBlueprintMath(root) {
    if (!isHydratableRoot(root)) return;
    if (typeof katex !== "object" || typeof katex.render !== "function") return;
    const resolvePrelude = function (m) {
      if (!(m instanceof Element)) return "";
      const table =
        window.bpTexPreludeTable && typeof window.bpTexPreludeTable === "object"
          ? window.bpTexPreludeTable
          : {};
      const preludeId = (m.getAttribute("data-bp-tex-prelude-id") || "").trim();
      if (preludeId && typeof table[preludeId] === "string") {
        return table[preludeId].trim();
      }
      const fallback = m.getAttribute("data-bp-tex-prelude");
      return typeof fallback === "string" ? fallback.trim() : "";
    };
    const renderAll = function (selector, displayMode) {
      root.querySelectorAll(selector).forEach(function (m) {
        if (!(m instanceof Element)) return;
        if (m.getAttribute("data-bp-math-rendered") === "1") return;
        try {
          const tex = m.textContent || "";
          const prelude = resolvePrelude(m);
          const renderInput = prelude ? prelude + "\n" + tex : tex;
          katex.render(renderInput, m, { throwOnError: false, displayMode: displayMode });
          m.setAttribute("data-bp-math-rendered", "1");
        } catch (_err) {}
      });
    };
    renderAll(".bp_math.inline", false);
    renderAll(".bp_math.display", true);
  }

  export function registerPreviewHydrator(name, fn) {
    if (typeof name !== "string" || name.length === 0) return;
    if (typeof fn !== "function") return;
    activePreviewHydrators().set(name, fn);
  }

  export function runPreviewHydrators(root, options) {
    const opts = options && typeof options === "object" ? options : {};
    if (!isHydratableRoot(root)) return;
    if (opts.inheritPageHydrators !== false) {
      activePreviewHydrators().forEach(function (fn, name) {
        runPreviewHydratorEntry(root, { name: String(name || ""), fn }, "registered");
      });
    }
    normalizePreviewHydrators(opts.hydrators).forEach(function (entry) {
      runPreviewHydratorEntry(root, entry, "options");
    });
  }

  export const previewRuntimeHydration = {
    previewHydrators,
    normalizePreviewHydrators,
    setTemplatePreviewDescriptorBinder,
    hydrateRenderedPreview,
    renderBlueprintMath,
    registerPreviewHydrator,
    runPreviewHydrators
  };

export default previewRuntimeHydration;
