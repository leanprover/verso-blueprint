  // Runtime-local diagnostics and page-local template capture.

  export function previewDebugEnabled() {
    try {
      return window.localStorage.getItem("bp-debug-preview") === "1";
    } catch (_err) {
      return false;
    }
  }

  export function previewDebugLabel(node) {
    if (!(node instanceof Element)) return String(node);
    const parts = [node.tagName.toLowerCase()];
    const cls = (node.getAttribute("class") || "").trim();
    const pid = (node.getAttribute("data-bp-preview-id") || "").trim();
    const pkey = (node.getAttribute("data-bp-preview-key") || "").trim();
    const title = (node.getAttribute("data-bp-preview-title") || "").trim();
    if (cls) parts.push("." + cls.replaceAll(" ", "."));
    if (pid) parts.push("pid=" + pid);
    if (pkey) parts.push("pkey=" + pkey);
    if (title) parts.push("title=" + title);
    return parts.join(" ");
  }

  export function previewDebug(eventName, payload) {
    if (!previewDebugEnabled()) return;
    try {
      console.log("[bp-preview]", eventName, payload || {});
    } catch (_err) {}
  }

  export function collectPreviewTemplates(root, selector, keyAttr) {
    const map = new Map();
    if (!(root instanceof Element || root instanceof Document)) return map;
    if (typeof selector !== "string" || selector.length === 0) return map;
    const keyName =
      typeof keyAttr === "string" && keyAttr.length > 0
        ? keyAttr
        : "data-bp-preview-label";
    root.querySelectorAll(selector).forEach(function (tpl) {
      if (!(tpl instanceof Element)) return;
      const label = tpl.getAttribute(keyName) || "";
      let html = "";
      if (tpl instanceof HTMLTemplateElement) {
        const content = tpl.content.cloneNode(true);
        if (content instanceof DocumentFragment) {
          const wrapper = document.createElement("div");
          wrapper.appendChild(content);
          html = (wrapper.innerHTML || "").trim();
        }
      }
      if (!html) {
        html = (tpl.innerHTML || "").trim();
      }
      if (label && html) {
        map.set(label, html);
      }
    });
    return map;
  }

  export function readHtml(entry) {
    if (typeof entry === "string") {
      return entry;
    }
    if (entry && typeof entry === "object" && typeof entry.html === "string") {
      return entry.html;
    }
    return "";
  }

  export function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  export function normalizePreviewMode(rawMode, fallback) {
    const defaultMode = fallback === "hover" || fallback === "pinned" ? fallback : "hover";
    const mode = String(rawMode || "").trim().toLowerCase();
    if (mode === "hover") return "hover";
    if (mode === "pinned") return "pinned";
    return defaultMode;
  }

  export function normalizePreviewPlacement(rawPlacement, fallback) {
    const defaultPlacement =
      fallback === "anchored" || fallback === "docked" ? fallback : "anchored";
    const placement = String(rawPlacement || "").trim().toLowerCase();
    if (placement === "anchored") return "anchored";
    if (placement === "docked") return "docked";
    return defaultPlacement;
  }

  export function readPanelBehavior(panel, defaults) {
    const defaultMode = normalizePreviewMode(defaults && defaults.mode, "hover");
    const defaultPlacement = normalizePreviewPlacement(defaults && defaults.placement, "anchored");
    if (!(panel instanceof Element)) {
      return {
        mode: defaultMode,
        placement: defaultPlacement,
        isPinned: defaultMode === "pinned",
        isHover: defaultMode === "hover",
        isAnchored: defaultPlacement === "anchored",
        isDocked: defaultPlacement === "docked"
      };
    }
    const rawMode = (panel.getAttribute("data-bp-preview-mode") || "").trim();
    const rawPlacement = (panel.getAttribute("data-bp-preview-placement") || "").trim();
    const mode = normalizePreviewMode(rawMode, defaultMode);
    const placement = normalizePreviewPlacement(rawPlacement, defaultPlacement);
    return {
      mode: mode,
      placement: placement,
      isPinned: mode === "pinned",
      isHover: mode === "hover",
      isAnchored: placement === "anchored",
      isDocked: placement === "docked"
    };
  }

  export function normalizePanelBehavior(panel, defaults, nextBehavior) {
    const fallback = readPanelBehavior(panel, defaults);
    if (!nextBehavior || typeof nextBehavior !== "object") return fallback;
    const mode = normalizePreviewMode(nextBehavior.mode, fallback.mode);
    const placement = normalizePreviewPlacement(nextBehavior.placement, fallback.placement);
    return {
      mode: mode,
      placement: placement,
      isPinned: mode === "pinned",
      isHover: mode === "hover",
      isAnchored: placement === "anchored",
      isDocked: placement === "docked"
    };
  }

  export function readStringOption(options, name, fallback) {
    return options && typeof options[name] === "string" && options[name].length > 0
      ? options[name]
      : fallback;
  }

  export function readObjectOption(options, name, fallback) {
    return options && options[name] && typeof options[name] === "object"
      ? options[name]
      : fallback;
  }

  export function readNumberOption(options, name, fallback) {
    return options && Number.isFinite(options[name])
      ? options[name]
      : fallback;
  }

  export function readFunctionOption(options, name, fallback) {
    return options && typeof options[name] === "function"
      ? options[name]
      : fallback;
  }

  export function readElementOption(options, name, fallback) {
    return options && options[name] instanceof Element
      ? options[name]
      : fallback;
  }

  export function readRootOption(options, name, fallback) {
    return options && (options[name] instanceof Element || options[name] instanceof Document)
      ? options[name]
      : fallback;
  }

  export const previewRuntimeBase = {
    previewDebugEnabled,
    previewDebugLabel,
    previewDebug,
    collectPreviewTemplates,
    readHtml,
    escapeHtml,
    normalizePreviewMode,
    normalizePreviewPlacement,
    readPanelBehavior,
    normalizePanelBehavior,
    readStringOption,
    readObjectOption,
    readNumberOption,
    readFunctionOption,
    readElementOption,
    readRootOption
  };

function blueprintDataApi(options) {
  const opts = options && typeof options === "object" ? options : {};
  return opts.dataApi && typeof opts.dataApi === "object" ? opts.dataApi : null;
}

export function requireBlueprintDataApi(options) {
  const dataApi = blueprintDataApi(options);
  if (!dataApi) {
    throw new Error("Blueprint data API missing; call through createPreview() or createBlueprintDataApi()");
  }
  return dataApi;
}

export function loadManifestEntry(previewKey, options) {
  const dataApi = requireBlueprintDataApi(options);
  return dataApi.loadManifestEntry(previewKey, options);
}
