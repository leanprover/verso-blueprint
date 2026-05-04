/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.Data.Options

namespace Informal.Commands

open Lean

register_option verso.blueprint.debug.commands : Bool := {
  defValue := false
  descr := "Emit debug info logs for blueprint graph, summary, and bibliography commands"
}

def blueprintTokensCss : String := r##"
:root {
  --bp-color-surface: #ffffff;
  --bp-color-surface-muted: #f8fafc;
  --bp-color-surface-subtle: #f9fafb;
  --bp-color-surface-modern: #f8fbff;
  --bp-color-surface-warn: #fff7ed;
  --bp-color-surface-warn-soft: #ffedd5;
  --bp-color-surface-note: #fffbeb;
  --bp-color-border: #cbd5e1;
  --bp-color-border-soft: #e2e8f0;
  --bp-color-border-muted: #d1d5db;
  --bp-color-border-panel: #dbe4ee;
  --bp-color-border-strong: #94a3b8;
  --bp-color-text-strong: #0f172a;
  --bp-color-text: #111827;
  --bp-color-text-muted: #334155;
  --bp-color-text-subtle: #475569;
  --bp-color-text-faint: #64748b;
  --bp-color-accent-success: #16a34a;
  --bp-color-accent-warning: #ca8a04;
  --bp-color-accent-danger: #dc2626;
  --bp-color-accent-info: #7c3aed;
  --bp-color-status-success-text: #166534;
  --bp-color-status-warning-text: #a16207;
  --bp-color-status-warning-strong: #9a3412;
  --bp-color-status-warning-border: #fdba74;
  --bp-color-status-warning-border-soft: #fed7aa;
  --bp-color-status-error-text: #b91c1c;
  --bp-color-status-error-strong: #991b1b;
  --bp-color-status-error-border-soft: #fecaca;
  --bp-color-status-note-border: #fcd34d;
  --bp-color-status-note-text: #92400e;
  --bp-color-focus-border: #93c5fd;
  --bp-color-focus-surface: #eff6ff;
  --bp-color-focus-ring: rgba(59, 130, 246, 0.12);
  --bp-color-selection: rgba(59, 130, 246, 0.18);
  --bp-color-selection-ring: rgba(59, 130, 246, 0.22);
  --bp-color-selection-surface-strong: rgba(59, 130, 246, 0.28);
  --bp-color-selection-surface-soft: rgba(59, 130, 246, 0.14);
  --bp-color-selection-surface-faint: rgba(59, 130, 246, 0.1);
  --bp-color-selection-shadow-strong: rgba(59, 130, 246, 0.3);
  --bp-color-selection-shadow-soft: rgba(59, 130, 246, 0.24);
  --bp-color-selection-shadow-faint: rgba(59, 130, 246, 0.16);
  --bp-color-target-ring: rgba(37, 99, 235, 0.22);
  --bp-color-target-surface: rgba(37, 99, 235, 0.14);
  --bp-color-target-ring-strong: rgba(37, 99, 235, 0.28);
  --bp-color-modern-border: #d6deea;
  --bp-color-modern-surface-alt: #f5f9ff;
  --bp-color-modern-caption: #e0ecff;
  --bp-color-bold-surface-glow-1: rgba(251, 191, 36, 0.2);
  --bp-color-bold-surface-glow-2: rgba(16, 185, 129, 0.2);
  --bp-color-bold-link: #7c2d12;
  --bp-color-bold-label: #f59e0b;
  --bp-color-biblio-border: #d6ccff;
  --bp-color-biblio-surface: #faf7ff;
  --bp-color-biblio-border-soft: #e9ddff;
  --bp-color-biblio-surface-soft: #fdfbff;
  --bp-color-biblio-link: #4c1d95;
  --bp-radius-sm: 0.35rem;
  --bp-radius-md: 0.45rem;
  --bp-radius-lg: 0.5rem;
  --bp-radius-xl: 0.55rem;
  --bp-radius-2xl: 0.7rem;
  --bp-radius-3xl: 0.85rem;
  --bp-radius-pill: 999px;
  --bp-shadow-sm: 0 4px 14px rgba(15, 23, 42, 0.1);
  --bp-shadow-md: 0 10px 24px rgba(15, 23, 42, 0.16);
  --bp-shadow-lg: 0 12px 28px rgba(15, 23, 42, 0.18);
  --bp-shadow-modern: 0 6px 18px rgba(15, 23, 42, 0.08);
  --bp-shadow-bold: 0 7px 0 var(--bp-color-text-strong);
  --bp-shadow-bold-lg: 0 9px 0 var(--bp-color-text-strong);
}
"##

def previewPanelCss : String := r##"
.bp_preview_panel {
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-lg);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-md);
  padding: 0.65rem 0.75rem;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::before {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  top: -0.85rem;
  height: 0.85rem;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::after {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  bottom: -0.85rem;
  height: 0.85rem;
}

.bp_preview_panel_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  margin-bottom: 0.4rem;
}

.bp_preview_panel_title {
  font-weight: 700;
  color: var(--bp-color-text);
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.bp_preview_panel_close {
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-sm);
  background: var(--bp-color-surface);
  color: var(--bp-color-text-strong);
  font-size: 0.72rem;
  font-weight: 600;
  line-height: 1;
  padding: 0.25rem 0.45rem;
  cursor: pointer;
}

.bp_preview_panel[data-bp-preview-mode="hover"] .bp_preview_panel_close {
  display: none;
}

.bp_preview_panel_body {
  border-left: 2px solid var(--bp-color-border-soft);
  overflow: auto;
}
"##

def previewHoverUtilsJs : String := r##"(function () {
  if (window.bpPreviewUtils) return;

  function previewDebugEnabled() {
    try {
      return window.localStorage.getItem("bp-debug-preview") === "1";
    } catch (_err) {
      return false;
    }
  }

  function previewDebugLabel(node) {
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

  function previewDebug(eventName, payload) {
    const entry = {
      at: Date.now(),
      event: eventName,
      payload: payload || {}
    };
    try {
      if (!Array.isArray(window.bpPreviewTrace)) {
        window.bpPreviewTrace = [];
      }
      window.bpPreviewTrace.push(entry);
      if (window.bpPreviewTrace.length > 200) {
        window.bpPreviewTrace.splice(0, window.bpPreviewTrace.length - 200);
      }
    } catch (_err) {}
    if (!previewDebugEnabled()) return;
    try {
      console.log("[bp-preview]", eventName, payload || {});
    } catch (_err) {}
  }

  function collectPreviewTemplates(root, selector, keyAttr) {
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

  function readPreviewTemplate(entry) {
    if (typeof entry === "string") {
      return entry;
    }
    if (entry && typeof entry === "object" && typeof entry.html === "string") {
      return entry.html;
    }
    return "";
  }

  function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function decodeSharedPreviewManifest(data) {
    const map = new Map();
    const entries =
      Array.isArray(data)
        ? data
        : data && typeof data === "object" && Array.isArray(data.previews)
          ? data.previews
          : [];
    entries.forEach(function (entry) {
      if (!entry || typeof entry !== "object") return;
      const key = String(entry.key || "").trim();
      const html = typeof entry.html === "string" ? entry.html.trim() : "";
      if (!key || !html) return;
      map.set(key, entry);
    });
    return map;
  }

  function readSharedPreviewManifestStatus() {
    const status = window.bpSharedPreviewManifestStatus;
    if (status && typeof status === "object") return status;
    return {
      state: "idle",
      attempts: 0,
      url: sharedPreviewManifestUrl(),
      lastError: "",
      entryCount: 0
    };
  }

  function setSharedPreviewManifestStatus(status) {
    window.bpSharedPreviewManifestStatus = status;
    return status;
  }

  function sharedPreviewManifestDiagnosticHtml(previewKey) {
    const status = readSharedPreviewManifestStatus();
    const trimmedKey = typeof previewKey === "string" ? previewKey.trim() : "";
    const keyHtml = trimmedKey ? "<code>" + escapeHtml(trimmedKey) + "</code>" : "this preview";
    if (status.state === "error") {
      const errorHtml = status.lastError
        ? "<p>Last load error: <code>" + escapeHtml(status.lastError) + "</code></p>"
        : "";
      return (
        "<div class=\"bp_manifest_preview_notice\">" +
        "<p><strong>Preview manifest unavailable.</strong></p>" +
        "<p>Blueprint previews require <code>-verso-data/blueprint-preview-manifest.json</code>. " +
        "Rebuild the site or retry after the current build finishes.</p>" +
        "<p>Requested preview: " + keyHtml + "</p>" +
        errorHtml +
        "</div>"
      );
    }
    if (status.state === "ready" && trimmedKey) {
      return (
        "<div class=\"bp_manifest_preview_notice\">" +
        "<p><strong>Preview entry missing from manifest.</strong></p>" +
        "<p>Requested preview: " + keyHtml + "</p>" +
        "<p>The site emitted a manifest, but this preview key was not present.</p>" +
        "</div>"
      );
    }
    return "";
  }

  function sharedPreviewManifestUrl() {
    try {
      const url = new URL(window.location.href);
      const markers = ["/html-multi/", "/html-single/"];
      for (const marker of markers) {
        const idx = url.pathname.indexOf(marker);
        if (idx >= 0) {
          const rootPath = url.pathname.slice(0, idx + marker.length);
          return rootPath + "-verso-data/blueprint-preview-manifest.json";
        }
      }
    } catch (_err) {}
    return "-verso-data/blueprint-preview-manifest.json";
  }

  function fetchSharedPreviewManifestJson(url) {
    return fetch(url).then(function (resp) {
      if (!resp.ok) {
        throw new Error("HTTP " + resp.status + " while loading " + url);
      }
      return resp.json();
    });
  }

  function fetchSharedPreviewManifestData() {
    const jsonUrl = sharedPreviewManifestUrl();
    return fetchSharedPreviewManifestJson(jsonUrl).then(function (data) {
      return { data: data, url: jsonUrl };
    });
  }

  function loadSharedPreviewManifest() {
    if (window.bpSharedPreviewManifest instanceof Map) {
      return Promise.resolve(window.bpSharedPreviewManifest);
    }
    if (window.bpSharedPreviewManifestPromise) {
      return window.bpSharedPreviewManifestPromise;
    }
    const url = sharedPreviewManifestUrl();
    const previousStatus = readSharedPreviewManifestStatus();
    const attempts =
      Number.isFinite(previousStatus.attempts) ? previousStatus.attempts + 1 : 1;
    setSharedPreviewManifestStatus({
      state: "loading",
      attempts: attempts,
      url: url,
      lastError: "",
      entryCount: 0
    });
    let promise = null;
    promise = fetchSharedPreviewManifestData()
      .then(function (result) {
        const map = decodeSharedPreviewManifest(result.data);
        window.bpSharedPreviewManifest = map;
        setSharedPreviewManifestStatus({
          state: "ready",
          attempts: attempts,
          url: result.url,
          lastError: "",
          entryCount: map.size
        });
        return map;
      })
      .catch(function (err) {
        const message =
          err && typeof err.message === "string" && err.message.length > 0
            ? err.message
            : String(err);
        window.bpSharedPreviewManifest = null;
        setSharedPreviewManifestStatus({
          state: "error",
          attempts: attempts,
          url: url,
          lastError: message,
          entryCount: 0
        });
        previewDebug("sharedManifest.loadFailed", {
          url: url,
          attempts: attempts,
          error: message
        });
        try {
          console.error("[bp-preview] shared preview manifest load failed", {
            url: url,
            error: message
          });
        } catch (_consoleErr) {}
        return new Map();
      })
      .then(function (map) {
        if (window.bpSharedPreviewManifestPromise === promise) {
          window.bpSharedPreviewManifestPromise = null;
        }
        return map;
      });
    window.bpSharedPreviewManifestPromise = promise;
    return promise;
  }

  function readSharedPreviewEntry(previewKey) {
    if (typeof previewKey !== "string" || previewKey.length === 0) return null;
    const map = window.bpSharedPreviewManifest;
    if (!(map instanceof Map)) return null;
    return map.get(previewKey) || null;
  }

  function statementPreviewKey(label) {
    const trimmed = typeof label === "string" ? label.trim() : "";
    return trimmed ? trimmed + "--statement" : "";
  }

  async function loadSharedPreviewEntry(previewKey) {
    const exact = readSharedPreviewEntry(previewKey);
    if (exact) return exact;
    const manifest = await loadSharedPreviewManifest();
    if (!(manifest instanceof Map)) return null;
    if (typeof previewKey === "string" && previewKey.length > 0 && manifest.has(previewKey)) {
      return manifest.get(previewKey) || null;
    }
    return null;
  }

  function renderMath(root) {
    if (!(root instanceof Element)) return;
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

  function bindCloseOnce(button, onClose) {
    if (!(button instanceof Element)) return;
    if (button.getAttribute("data-bp-bound") === "1") return;
    if (typeof onClose !== "function") return;
    button.setAttribute("data-bp-bound", "1");
    button.addEventListener("click", function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      onClose(ev);
    });
  }

  function readAnchorRect(anchor) {
    if (anchor instanceof Element) {
      return anchor.getBoundingClientRect();
    }
    if (
      anchor &&
      typeof anchor === "object" &&
      Number.isFinite(anchor.left) &&
      Number.isFinite(anchor.right) &&
      Number.isFinite(anchor.top) &&
      Number.isFinite(anchor.bottom)
    ) {
      return anchor;
    }
    return null;
  }

  function positionAnchoredPanel(panel, anchor, margin, offset) {
    if (!(panel instanceof Element)) return;
    const rect = readAnchorRect(anchor);
    if (!rect) return;
    const safeMargin = Number.isFinite(margin) ? margin : 12;
    const safeOffset = Number.isFinite(offset) ? offset : 10;
    const panelRect = panel.getBoundingClientRect();
    const panelWidth = panelRect.width || Math.min(520, window.innerWidth - safeMargin * 2);
    const panelHeight = panelRect.height || Math.min(420, window.innerHeight - safeMargin * 2);
    let left = rect.left;
    if (left + panelWidth > window.innerWidth - safeMargin) {
      left = window.innerWidth - panelWidth - safeMargin;
    }
    left = Math.max(safeMargin, left);
    let top = rect.bottom + safeOffset;
    if (top + panelHeight > window.innerHeight - safeMargin) {
      top = rect.top - panelHeight - safeOffset;
    }
    top = Math.max(safeMargin, top);
    panel.style.left = left + "px";
    panel.style.top = top + "px";
  }

  function shouldKeepOpen(nextTarget, trigger, panel) {
    if (!(nextTarget instanceof Element)) return false;
    if (trigger instanceof Element && trigger.contains(nextTarget)) return true;
    if (panel instanceof Element && panel.contains(nextTarget)) return true;
    const inlinePanel = document.getElementById("bp-inline-preview-panel");
    if (inlinePanel instanceof Element && inlinePanel.contains(nextTarget)) return true;
    return false;
  }

  function readPanelBehavior(panel, defaults) {
    const defaultMode =
      defaults && (defaults.mode === "hover" || defaults.mode === "pinned")
        ? defaults.mode
        : "hover";
    const defaultPlacement =
      defaults && (defaults.placement === "anchored" || defaults.placement === "docked")
        ? defaults.placement
        : "anchored";
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
    const mode = rawMode === "hover" || rawMode === "pinned" ? rawMode : defaultMode;
    const placement =
      rawPlacement === "anchored" || rawPlacement === "docked" ? rawPlacement : defaultPlacement;
    return {
      mode: mode,
      placement: placement,
      isPinned: mode === "pinned",
      isHover: mode === "hover",
      isAnchored: placement === "anchored",
      isDocked: placement === "docked"
    };
  }

  function resetPanelPosition(panel) {
    if (!(panel instanceof Element)) return;
    panel.style.left = "";
    panel.style.top = "";
  }

  function configureCloseButton(closeButton, onClose, behavior) {
    if (!(closeButton instanceof Element)) return;
    const pinned = !!(behavior && behavior.isPinned);
    closeButton.hidden = !pinned;
    closeButton.style.display = pinned ? "" : "none";
    closeButton.setAttribute("aria-hidden", pinned ? "false" : "true");
    closeButton.tabIndex = pinned ? 0 : -1;
    if (!pinned) return;
    bindCloseOnce(closeButton, onClose);
  }

  function pointerWithinPanel(panel, ev) {
    if (!(panel instanceof Element)) return false;
    if (!ev || !Number.isFinite(ev.clientX) || !Number.isFinite(ev.clientY)) return false;
    const rect = panel.getBoundingClientRect();
    return (
      ev.clientX >= rect.left &&
      ev.clientX <= rect.right &&
      ev.clientY >= rect.top &&
      ev.clientY <= rect.bottom
    );
  }

  function registerPreviewHydrator(name, fn) {
    if (typeof name !== "string" || name.length === 0) return;
    if (typeof fn !== "function") return;
    let registry = window.bpPreviewHydrators;
    if (!(registry instanceof Map)) {
      registry = new Map();
      window.bpPreviewHydrators = registry;
    }
    registry.set(name, fn);
  }

  function hydratePreviewSubtree(root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    const registry = window.bpPreviewHydrators;
    if (!(registry instanceof Map)) return;
    registry.forEach(function (fn) {
      if (typeof fn !== "function") return;
      try {
        fn(root);
      } catch (_err) {}
    });
  }

  function hidePanelContent(panel, titleNode, bodyNode) {
    if (!(panel instanceof Element)) return;
    panel.hidden = true;
    if (titleNode instanceof Element) titleNode.textContent = "";
    if (bodyNode instanceof Element) bodyNode.innerHTML = "";
  }

  function showPanelContent(panel, titleNode, bodyNode, heading, html, behavior, anchor, margin, offset) {
    if (!(panel instanceof Element) || !(titleNode instanceof Element) || !(bodyNode instanceof Element)) {
      return false;
    }
    if (typeof html !== "string" || html.length === 0) {
      hidePanelContent(panel, titleNode, bodyNode);
      return false;
    }
    const safeMargin = Number.isFinite(margin) ? margin : 12;
    const safeOffset = Number.isFinite(offset) ? offset : 10;
    titleNode.textContent = typeof heading === "string" ? heading : "";
    bodyNode.innerHTML = html;
    hydratePreviewSubtree(bodyNode);
    renderMath(bodyNode);
    panel.hidden = false;
    if (behavior && behavior.isAnchored && readAnchorRect(anchor)) {
      positionAnchoredPanel(panel, anchor, safeMargin, safeOffset);
    } else {
      resetPanelPosition(panel);
    }
    return true;
  }

  function bindTemplatePreview(options) {
    const root =
      options && (options.root instanceof Element || options.root instanceof Document)
        ? options.root
        : document;
    const previewRoot =
      options && (options.previewRoot instanceof Element || options.previewRoot instanceof Document)
        ? options.previewRoot
        : root;
    const triggerRoot =
      options && (options.triggerRoot instanceof Element || options.triggerRoot instanceof Document)
        ? options.triggerRoot
        : root;
    const panel = options && options.panel instanceof Element ? options.panel : null;
    const templateSelector =
      options && typeof options.templateSelector === "string" ? options.templateSelector : "";
    const triggerSelector =
      options && typeof options.triggerSelector === "string" ? options.triggerSelector : "";
    const keyAttr =
      options && typeof options.keyAttr === "string" && options.keyAttr.length > 0
        ? options.keyAttr
        : "data-bp-preview-label";
    const titleAttr =
      options && typeof options.titleAttr === "string" && options.titleAttr.length > 0
        ? options.titleAttr
        : keyAttr;
    const titleSelector =
      options && typeof options.titleSelector === "string" ? options.titleSelector : "";
    const bodySelector =
      options && typeof options.bodySelector === "string" ? options.bodySelector : "";
    const closeSelector =
      options && typeof options.closeSelector === "string" ? options.closeSelector : "";
    const triggerBoundAttr =
      options && typeof options.triggerBoundAttr === "string" && options.triggerBoundAttr.length > 0
        ? options.triggerBoundAttr
        : "data-bp-bound";
    const defaults = options && typeof options.defaults === "object" ? options.defaults : {};
    const margin =
      options && Number.isFinite(options.margin) ? options.margin : 12;
    const offset =
      options && Number.isFinite(options.offset) ? options.offset : 10;
    const readKey =
      options && typeof options.readKey === "function"
        ? options.readKey
        : function (trigger) {
            if (!(trigger instanceof Element)) return "";
            return (trigger.getAttribute(keyAttr) || "").trim();
          };
    const readTitle =
      options && typeof options.readTitle === "function"
        ? options.readTitle
        : function (trigger, key) {
            if (!(trigger instanceof Element)) return key;
            const heading = (trigger.getAttribute(titleAttr) || "").trim();
            return heading || key;
          };
    const readLookupKey =
      options && typeof options.readLookupKey === "function"
        ? options.readLookupKey
        : function (trigger) {
            if (!(trigger instanceof Element)) return "";
            return (trigger.getAttribute("data-bp-preview-key") || "").trim();
          };
    const allowSharedManifest = !!(options && options.allowSharedManifest);

    const previewMap = collectPreviewTemplates(previewRoot, templateSelector, keyAttr);
    const triggers = triggerRoot.querySelectorAll(triggerSelector);
    const title = panel ? panel.querySelector(titleSelector) : null;
    const body = panel ? panel.querySelector(bodySelector) : null;
    const close = panel ? panel.querySelector(closeSelector) : null;
    if (!panel || !(title instanceof Element) || !(body instanceof Element) || (!allowSharedManifest && previewMap.size === 0)) {
      if (panel) hidePanelContent(panel, title, body);
      return null;
    }
    if (triggers.length === 0) {
      hidePanelContent(panel, title, body);
      return null;
    }
    const behavior = readPanelBehavior(panel, defaults);
    let activeTrigger = null;
    let hideTimer = null;
    let showRequestToken = 0;

    function cancelHide() {
      if (hideTimer !== null) {
        clearTimeout(hideTimer);
        hideTimer = null;
      }
    }

    function hidePanel() {
      cancelHide();
      showRequestToken += 1;
      hidePanelContent(panel, title, body);
      activeTrigger = null;
    }

    function scheduleHide() {
      cancelHide();
      if (!behavior.isHover) {
        hidePanel();
        return;
      }
      hideTimer = window.setTimeout(function () {
        hideTimer = null;
        hidePanel();
      }, 180);
    }

    function pointerWithinPanel(ev) {
      if (!(panel instanceof Element)) return false;
      if (!ev || !Number.isFinite(ev.clientX) || !Number.isFinite(ev.clientY)) return false;
      const rect = panel.getBoundingClientRect();
      return (
        ev.clientX >= rect.left &&
        ev.clientX <= rect.right &&
        ev.clientY >= rect.top &&
        ev.clientY <= rect.bottom
      );
    }

    function positionPanel(anchor) {
      if (!behavior.isAnchored) {
        resetPanelPosition(panel);
        return;
      }
      if (!(anchor instanceof Element)) return;
      positionAnchoredPanel(panel, anchor, margin, offset);
    }

    async function resolveTriggerHtml(trigger, key) {
      const localEntry = previewMap.get(key);
      const localHtml = readPreviewTemplate(localEntry);
      if (localHtml) return localHtml;
      if (!allowSharedManifest) return "";
      const lookupKey = readLookupKey(trigger, key, localEntry);
      const sharedEntry =
        typeof loadSharedPreviewEntry === "function"
          ? await loadSharedPreviewEntry(lookupKey)
          : null;
      const sharedHtml = readPreviewTemplate(sharedEntry);
      if (sharedHtml) return sharedHtml;
      return sharedPreviewManifestDiagnosticHtml(lookupKey || key);
    }

    async function showFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      const key = readKey(trigger);
      const requestToken = ++showRequestToken;
      const html = await resolveTriggerHtml(trigger, key);
      if (requestToken !== showRequestToken) return;
      if (!key || !html) {
        hidePanel();
        return;
      }
      activeTrigger = trigger;
      const heading = readTitle(trigger, key);
      showPanelContent(panel, title, body, heading, html, behavior, trigger, margin, offset);
    }

    configureCloseButton(close, hidePanel, behavior);

    triggers.forEach(function (trigger) {
      if (!(trigger instanceof Element)) return;
      if (trigger.getAttribute(triggerBoundAttr) === "1") return;
      trigger.setAttribute(triggerBoundAttr, "1");
      trigger.addEventListener("mouseenter", function () {
        cancelHide();
        showFromTrigger(trigger);
      });
      trigger.addEventListener("focusin", function () {
        cancelHide();
        showFromTrigger(trigger);
      });
      trigger.addEventListener("mouseleave", function (ev) {
        if (!behavior.isHover) return;
        if (shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
        scheduleHide();
      });
      trigger.addEventListener("focusout", function (ev) {
        if (!behavior.isHover) return;
        if (shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
        scheduleHide();
      });
    });

    panel.addEventListener("mouseenter", function () {
      cancelHide();
    });
    panel.addEventListener("focusin", function () {
      cancelHide();
    });
    panel.addEventListener("mouseleave", function (ev) {
      if (!behavior.isHover) return;
      if (shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      scheduleHide();
    });
    panel.addEventListener("focusout", function (ev) {
      if (!behavior.isHover) return;
      if (shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      scheduleHide();
    });

    document.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape") {
        hidePanel();
      }
    });
    window.addEventListener("resize", function () {
      if (behavior.isAnchored && activeTrigger && !panel.hidden) positionPanel(activeTrigger);
    });
    window.addEventListener(
      "scroll",
      function () {
        if (behavior.isAnchored && activeTrigger && !panel.hidden) positionPanel(activeTrigger);
      },
      true
    );

    return {
      previewMap: previewMap,
      behavior: behavior,
      hidePanel: hidePanel,
      showFromTrigger: showFromTrigger
    };
  }

  window.bpPreviewUtils = {
    collectPreviewTemplates: collectPreviewTemplates,
    readPreviewTemplate: readPreviewTemplate,
    loadSharedPreviewManifest: loadSharedPreviewManifest,
    readSharedPreviewManifestStatus: readSharedPreviewManifestStatus,
    readSharedPreviewEntry: readSharedPreviewEntry,
    statementPreviewKey: statementPreviewKey,
    loadSharedPreviewEntry: loadSharedPreviewEntry,
    renderMath: renderMath,
    bindCloseOnce: bindCloseOnce,
    positionAnchoredPanel: positionAnchoredPanel,
    shouldKeepOpen: shouldKeepOpen,
    readPanelBehavior: readPanelBehavior,
    resetPanelPosition: resetPanelPosition,
    configureCloseButton: configureCloseButton,
    pointerWithinPanel: pointerWithinPanel,
    registerPreviewHydrator: registerPreviewHydrator,
    hydratePreviewSubtree: hydratePreviewSubtree,
    previewDebug: previewDebug,
    previewDebugLabel: previewDebugLabel,
    hidePanelContent: hidePanelContent,
    showPanelContent: showPanelContent,
    bindTemplatePreview: bindTemplatePreview
  };
})();"##

def inlinePreviewCss : String := r##"
.bp_inline_preview_ref {
  cursor: help;
}

.bp_inline_preview_panel {
  position: fixed;
  z-index: 70;
  min-width: 18rem;
  max-width: min(34rem, 86vw);
  max-height: min(26rem, 80vh);
  overflow: hidden;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-lg);
}

.bp_inline_preview_panel_child {
  z-index: 71;
}

.bp_inline_preview_panel[data-bp-preview-placement="anchored"]::before {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  top: -0.85rem;
  height: 0.85rem;
}

.bp_inline_preview_panel[data-bp-preview-placement="docked"] {
  top: 0.9rem;
  right: 0.9rem;
  left: auto;
}

.bp_inline_preview_panel_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.6rem;
  padding: 0.4rem 0.55rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: var(--bp-color-surface-muted);
}

.bp_inline_preview_panel_title {
  font-size: 0.82rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_inline_preview_panel_close {
  border: 1px solid var(--bp-color-border);
  border-radius: 0.3rem;
  background: var(--bp-color-surface);
  color: var(--bp-color-text-muted);
  font-size: 0.72rem;
  line-height: 1;
  padding: 0.2rem 0.35rem;
  cursor: pointer;
}

.bp_inline_preview_panel_body {
  padding: 0.5rem 0.6rem 0.55rem;
  max-height: min(22rem, 70vh);
  overflow: auto;
  font-size: 0.8rem;
}

.bp_bibliography_hover_entry {
  border: 1px solid var(--bp-color-border-soft);
  border-radius: 0.4rem;
  padding: 0.35rem 0.45rem;
  background: var(--bp-color-surface-muted);
}

.bp_bibliography_hover_entry .citation {
  display: block;
  line-height: 1.35;
}

.bp_bibliography_hover_meta {
  margin-top: 0.42rem;
  display: flex;
  align-items: baseline;
  gap: 0.42rem;
  flex-wrap: wrap;
}

.bp_bibliography_hover_meta_label {
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-faint);
}

.bp_bibliography_hover_meta_value {
  font-size: 0.76rem;
  font-weight: 600;
  color: var(--bp-color-text-strong);
}

.bp_code_hover_section {
  margin-top: 0.28rem;
}

.bp_code_hover_label {
  font-weight: 600;
  color: var(--bp-color-text-muted);
}

.bp_code_hover_list {
  margin: 0.12rem 0 0;
  padding-left: 1.1rem;
}

.bp_code_hover_list code {
  font-size: 0.76rem;
}

.bp_code_hover_none {
  color: var(--bp-color-text-faint);
  font-style: italic;
}

.bp_inline_preview_panel[data-bp-preview-mode="hover"] .bp_inline_preview_panel_close {
  display: none;
}
"##

def openTargetDetailsJs : String := r##"(function () {
  function openFromHash() {
    if (!window.location.hash) return;
    const id = decodeURIComponent(window.location.hash.slice(1));
    if (!id) return;
    const target = document.getElementById(id);
    if (!target) return;
    const details = target.matches("details") ? target : target.closest("details");
    if (details) details.open = true;
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", openFromHash);
  } else {
    openFromHash();
  }
  window.addEventListener("hashchange", openFromHash);
})();"##

def inlineLinkPreviewJs : String := r##"(function () {
  const triggerSelector = ".bp_inline_preview_ref[data-bp-preview-id]";

  function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function fallbackInlinePreviewHtml(trigger, key) {
    if (!(trigger instanceof Element)) return "";
    const title = (trigger.getAttribute("data-bp-preview-title") || key || "").trim();
    const label = (trigger.getAttribute("data-bp-preview-fallback-label") || "").trim();
    const detail = (trigger.getAttribute("data-bp-preview-fallback-detail") || "").trim();
    const text = (trigger.textContent || "").trim();
    let html = '<div class="bp_code_hover" role="tooltip">';
    html += '<div class="bp_code_hover_title">' + escapeHtml(title || "Preview") + "</div>";
    if (text.length > 0) {
      html += '<div class="bp_code_hover_section"><span class="bp_code_hover_label">Reference</span><ul class="bp_code_hover_list"><li>' +
        escapeHtml(text) + "</li></ul></div>";
    }
    if (label.length > 0) {
      html += '<div class="bp_code_hover_section"><span class="bp_code_hover_label">Blueprint label</span><ul class="bp_code_hover_list"><li><code>' +
        escapeHtml(label) + "</code></li></ul></div>";
    }
    if (detail.length > 0) {
      html += '<div class="bp_code_hover_section"><span class="bp_code_hover_label">Detail</span><ul class="bp_code_hover_list"><li>' +
        escapeHtml(detail) + "</li></ul></div>";
    }
    html += "</div>";
    return html;
  }

  function makePanel(id, extraClass) {
    const panel = document.createElement("aside");
    panel.id = id;
    panel.className =
      "bp_inline_preview_panel" + (typeof extraClass === "string" && extraClass.length > 0 ? " " + extraClass : "");
    panel.setAttribute("data-bp-preview-mode", "hover");
    panel.setAttribute("data-bp-preview-placement", "anchored");
    panel.hidden = true;
    panel.innerHTML =
      '<div class="bp_inline_preview_panel_header">' +
      '<div class="bp_inline_preview_panel_title"></div>' +
      '<button type="button" class="bp_inline_preview_panel_close" aria-label="Close inline preview">Close</button>' +
      "</div>" +
      '<div class="bp_inline_preview_panel_body"></div>';
    document.body.appendChild(panel);
    return panel;
  }

  function getPanel(id, extraClass) {
    const existing = document.getElementById(id);
    if (existing instanceof Element) return existing;
    return makePanel(id, extraClass);
  }

  function bindInlinePreview() {
    if (!(document.body instanceof Element)) return;
    if (document.body.getAttribute("data-bp-inline-preview-bound") === "1") return;
    document.body.setAttribute("data-bp-inline-preview-bound", "1");

    const previewUtils = window.bpPreviewUtils;
    if (
      !previewUtils ||
      typeof previewUtils.readPreviewTemplate !== "function" ||
      typeof previewUtils.readPanelBehavior !== "function" ||
      typeof previewUtils.showPanelContent !== "function" ||
      typeof previewUtils.hidePanelContent !== "function" ||
      typeof previewUtils.shouldKeepOpen !== "function" ||
      typeof previewUtils.configureCloseButton !== "function" ||
      typeof previewUtils.positionAnchoredPanel !== "function"
    ) {
      return;
    }
    const previewDebug =
      typeof previewUtils.previewDebug === "function"
        ? previewUtils.previewDebug
        : function () {};
    const previewDebugLabel =
      typeof previewUtils.previewDebugLabel === "function"
        ? previewUtils.previewDebugLabel
        : function (node) { return String(node); };

    const panel = getPanel("bp-inline-preview-panel", "");
    const title = panel.querySelector(".bp_inline_preview_panel_title");
    const body = panel.querySelector(".bp_inline_preview_panel_body");
    const close = panel.querySelector(".bp_inline_preview_panel_close");
    const childPanel = getPanel("bp-inline-preview-child-panel", "bp_inline_preview_panel_child");
    const childTitle = childPanel.querySelector(".bp_inline_preview_panel_title");
    const childBody = childPanel.querySelector(".bp_inline_preview_panel_body");
    const childClose = childPanel.querySelector(".bp_inline_preview_panel_close");
    if (
      !(title instanceof Element) || !(body instanceof Element) || !(close instanceof Element) ||
      !(childTitle instanceof Element) || !(childBody instanceof Element) || !(childClose instanceof Element)
    ) {
      return;
    }

    function makeBehavior(mode, placement) {
      return previewUtils.readPanelBehavior(null, { mode: mode, placement: placement });
    }

    let behavior = makeBehavior("hover", "anchored");
    let activeTrigger = null;
    let activeHost = null;
    let activePreviewKey = "";
    let hideTimer = null;
    let updatingPanel = false;
    let ignoreNextPanelExit = false;
    let showRequestToken = 0;
    let childActiveTrigger = null;
    let childPreviewKey = "";
    let childHideTimer = null;
    let childShowRequestToken = 0;
    const childBehavior = makeBehavior("hover", "anchored");

    function clearPanelSizeLock() {
      panel.style.width = "";
      panel.style.minHeight = "";
    }

    function lockPanelSizeToCurrentRect() {
      const rect = panel.getBoundingClientRect();
      if (!(rect.width > 0) || !(rect.height > 0)) return;
      panel.style.width = rect.width + "px";
      panel.style.minHeight = rect.height + "px";
    }

    function cancelHide() {
      if (hideTimer !== null) {
        clearTimeout(hideTimer);
        hideTimer = null;
      }
    }

    function cancelChildHide() {
      if (childHideTimer !== null) {
        clearTimeout(childHideTimer);
        childHideTimer = null;
      }
    }

    function readInlinePreviewHost(trigger) {
      if (!(trigger instanceof Element)) return null;
      const host = trigger.closest(".bp_used_by_panel, .bp_graph_preview, .bp_group_hover_preview");
      if (!(host instanceof Element)) return null;
      if (panel.contains(host)) return null;
      let kind = "generic";
      if (host.matches(".bp_used_by_panel")) {
        kind = "used-by";
      } else if (host.matches(".bp_graph_preview")) {
        kind = "graph";
      } else if (host.matches(".bp_group_hover_preview")) {
        kind = "graph-group";
      }
      return {
        element: host,
        kind: kind,
        behavior: makeBehavior("hover", "anchored")
      };
    }

    function positionDockedPanel(hostInfo) {
      if (!hostInfo || !(hostInfo.element instanceof Element)) return;
      const margin = 12;
      const gap = 12;
      const hostRect = hostInfo.element.getBoundingClientRect();
      const panelRect = panel.getBoundingClientRect();
      const panelWidth = panelRect.width || Math.min(520, window.innerWidth - margin * 2);
      const panelHeight = panelRect.height || Math.min(420, window.innerHeight - margin * 2);
      let left = hostRect.right + gap;
      if (left + panelWidth > window.innerWidth - margin) {
        left = hostRect.left - panelWidth - gap;
      }
      left = Math.max(margin, Math.min(left, window.innerWidth - panelWidth - margin));
      let top = hostRect.top;
      if (top + panelHeight > window.innerHeight - margin) {
        top = window.innerHeight - panelHeight - margin;
      }
      top = Math.max(margin, top);
      panel.style.left = left + "px";
      panel.style.top = top + "px";
    }

    function applyBehavior(nextBehavior, hostInfo) {
      behavior = nextBehavior || makeBehavior("hover", "anchored");
      activeHost = hostInfo || null;
      panel.setAttribute("data-bp-preview-mode", behavior.mode);
      panel.setAttribute("data-bp-preview-placement", behavior.placement);
      if (activeHost && activeHost.kind) {
        panel.setAttribute("data-bp-inline-host", activeHost.kind);
      } else {
        panel.removeAttribute("data-bp-inline-host");
      }
      previewUtils.configureCloseButton(close, hidePanel, behavior);
    }

    function bindInlinePreviewTriggers(root) {
      if (!(root instanceof Element || root instanceof Document)) return;
      root.querySelectorAll(triggerSelector).forEach(function (trigger) {
        if (!(trigger instanceof Element)) return;
        if (trigger.getAttribute("data-bp-inline-bound") === "1") return;
        trigger.setAttribute("data-bp-inline-bound", "1");
        const triggerKey = (trigger.getAttribute("data-bp-preview-id") || "").trim();
        const triggerInsidePanel = panel.contains(trigger) || childPanel.contains(trigger);
        trigger.addEventListener("mouseenter", function () {
          if (triggerInsidePanel) {
            cancelHide();
            cancelChildHide();
            showChildFromTrigger(trigger);
          } else {
            cancelHide();
            showFromTrigger(trigger);
          }
        });
        trigger.addEventListener("focusin", function () {
          if (triggerInsidePanel) {
            cancelHide();
            cancelChildHide();
            showChildFromTrigger(trigger);
          } else {
            cancelHide();
            showFromTrigger(trigger);
          }
        });
        if (triggerInsidePanel) {
          trigger.addEventListener("mouseleave", function (ev) {
            if (childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
            if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, childPanel)) return;
            scheduleChildHide();
          });
          trigger.addEventListener("focusout", function (ev) {
            if (childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
            if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, childPanel)) return;
            scheduleChildHide();
          });
          return;
        }
        trigger.addEventListener("mouseleave", function (ev) {
          if (!behavior.isHover) return;
          if (!trigger.isConnected) return;
          if (triggerKey && activePreviewKey && triggerKey !== activePreviewKey) return;
          if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
          if (panel.matches(":hover") || panel.matches(":focus-within")) return;
          if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
          previewDebug("inline.trigger.mouseleave", {
            triggerKey: triggerKey,
            activePreviewKey: activePreviewKey,
            trigger: previewDebugLabel(trigger),
            relatedTarget: previewDebugLabel(ev.relatedTarget),
            panelHover: panel.matches(":hover"),
            panelFocus: panel.matches(":focus-within"),
            updatingPanel: updatingPanel
          });
          scheduleHide();
        });
        trigger.addEventListener("focusout", function (ev) {
          if (!behavior.isHover) return;
          if (!trigger.isConnected) return;
          if (triggerKey && activePreviewKey && triggerKey !== activePreviewKey) return;
          if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
          if (panel.matches(":hover") || panel.matches(":focus-within")) return;
          if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
          previewDebug("inline.trigger.focusout", {
            triggerKey: triggerKey,
            activePreviewKey: activePreviewKey,
            trigger: previewDebugLabel(trigger),
            relatedTarget: previewDebugLabel(ev.relatedTarget),
            panelHover: panel.matches(":hover"),
            panelFocus: panel.matches(":focus-within"),
            updatingPanel: updatingPanel
          });
          scheduleHide();
        });
      });
    }

    function refresh(root) {
      const scope = root instanceof Element || root instanceof Document ? root : document;
      bindInlinePreviewTriggers(scope);
    }

    function hidePanel() {
      cancelHide();
      showRequestToken += 1;
      hideChildPanel();
      previewDebug("inline.hide", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      clearPanelSizeLock();
      previewUtils.hidePanelContent(panel, title, body);
      activeTrigger = null;
      activeHost = null;
      activePreviewKey = "";
      applyBehavior(makeBehavior("hover", "anchored"), null);
    }

    function hideChildPanel() {
      cancelChildHide();
      childShowRequestToken += 1;
      previewUtils.hidePanelContent(childPanel, childTitle, childBody);
      childActiveTrigger = null;
      childPreviewKey = "";
    }

    function scheduleHide() {
      cancelHide();
      if (!behavior.isHover) {
        hidePanel();
        return;
      }
      hideTimer = window.setTimeout(function () {
        hideTimer = null;
        previewDebug("inline.scheduleHide.fire", {
          activePreviewKey: activePreviewKey,
          activeTrigger: previewDebugLabel(activeTrigger),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within"),
          updatingPanel: updatingPanel
        });
        hidePanel();
      }, 180);
    }

    function scheduleChildHide() {
      cancelChildHide();
      childHideTimer = window.setTimeout(function () {
        childHideTimer = null;
        hideChildPanel();
      }, 180);
    }

    async function resolvePreviewHtml(key, trigger) {
      const previewLookupKey =
        trigger instanceof Element
          ? (trigger.getAttribute("data-bp-preview-key") || "").trim()
          : "";
      if (previewLookupKey) {
        const manifestEntry =
          typeof previewUtils.readSharedPreviewEntry === "function"
            ? previewUtils.readSharedPreviewEntry(previewLookupKey)
            : null;
        const manifestHtml = previewUtils.readPreviewTemplate(manifestEntry);
        if (manifestHtml) return manifestHtml;
        if (typeof previewUtils.loadSharedPreviewManifest === "function") {
          const manifest = await previewUtils.loadSharedPreviewManifest();
          const asyncHtml =
            manifest instanceof Map
              ? previewUtils.readPreviewTemplate(manifest.get(previewLookupKey))
              : "";
          if (asyncHtml) return asyncHtml;
        }
      }
      return fallbackInlinePreviewHtml(trigger, key);
    }

    async function showChildFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      const key = (trigger.getAttribute("data-bp-preview-id") || "").trim();
      if (!key) {
        hideChildPanel();
        return;
      }
      const requestToken = ++childShowRequestToken;
      const html = await resolvePreviewHtml(key, trigger);
      if (requestToken !== childShowRequestToken) return;
      if (!html) {
        hideChildPanel();
        return;
      }
      const heading = (trigger.getAttribute("data-bp-preview-title") || key).trim() || key;
      cancelHide();
      cancelChildHide();
      childPreviewKey = key;
      childActiveTrigger = trigger;
      previewUtils.showPanelContent(childPanel, childTitle, childBody, heading, html, childBehavior, trigger, 12, 10);
    }

    async function showFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      if (panel.contains(trigger) || childPanel.contains(trigger)) {
        showChildFromTrigger(trigger);
        return;
      }
      const key = (trigger.getAttribute("data-bp-preview-id") || "").trim();
      if (!key) {
        hidePanel();
        return;
      }
      const requestToken = ++showRequestToken;
      const html = await resolvePreviewHtml(key, trigger);
      if (requestToken !== showRequestToken) return;
      if (!html) {
        hidePanel();
        return;
      }
      const heading = (trigger.getAttribute("data-bp-preview-title") || key).trim() || key;
      activePreviewKey = key;
      const inPanel = panel.contains(trigger);
      const hostInfo = inPanel ? activeHost : readInlinePreviewHost(trigger);
      applyBehavior(hostInfo ? hostInfo.behavior : makeBehavior("hover", "anchored"), hostInfo);
      updatingPanel = inPanel;
      previewDebug("inline.show", {
        key: key,
        inPanel: inPanel,
        trigger: previewDebugLabel(trigger),
        host: activeHost ? activeHost.kind : "",
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within")
      });
      if (inPanel) {
        lockPanelSizeToCurrentRect();
        activeTrigger = null;
        ignoreNextPanelExit = true;
        title.textContent = heading;
        body.innerHTML = html;
        previewUtils.hydratePreviewSubtree(body);
        previewUtils.renderMath(body);
        panel.hidden = false;
        if (behavior.isDocked && activeHost) {
          positionDockedPanel(activeHost);
        }
        window.setTimeout(function () {
          updatingPanel = false;
        }, 180);
      } else {
        hideChildPanel();
        clearPanelSizeLock();
        activeTrigger = trigger;
        previewUtils.showPanelContent(panel, title, body, heading, html, behavior, trigger, 12, 10);
        if (behavior.isDocked && activeHost) {
          positionDockedPanel(activeHost);
        }
      }
    }
    applyBehavior(behavior, null);
    previewUtils.configureCloseButton(childClose, hideChildPanel, childBehavior);
    panel.addEventListener("mouseenter", function () {
      cancelHide();
    });
    panel.addEventListener("focusin", function () {
      cancelHide();
    });
    panel.addEventListener("mouseleave", function (ev) {
      if (!behavior.isHover) return;
      if (updatingPanel) return;
      if (ignoreNextPanelExit) {
        ignoreNextPanelExit = false;
        previewDebug("inline.panel.mouseleave.ignored", {
          activePreviewKey: activePreviewKey,
          relatedTarget: previewDebugLabel(ev.relatedTarget),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within")
        });
        return;
      }
      if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
      if (previewUtils.pointerWithinPanel(panel, ev)) return;
      if (panel.matches(":hover") || panel.matches(":focus-within")) return;
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      previewDebug("inline.panel.mouseleave", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        relatedTarget: previewDebugLabel(ev.relatedTarget),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      scheduleHide();
    });
    panel.addEventListener("focusout", function (ev) {
      if (!behavior.isHover) return;
      if (updatingPanel) return;
      if (ignoreNextPanelExit) {
        ignoreNextPanelExit = false;
        previewDebug("inline.panel.focusout.ignored", {
          activePreviewKey: activePreviewKey,
          relatedTarget: previewDebugLabel(ev.relatedTarget),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within")
        });
        return;
      }
      if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
      if (panel.matches(":hover") || panel.matches(":focus-within")) return;
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      previewDebug("inline.panel.focusout", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        relatedTarget: previewDebugLabel(ev.relatedTarget),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      scheduleHide();
    });
    document.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape") {
        hidePanel();
      }
    });
    childPanel.addEventListener("mouseenter", function () {
      cancelHide();
      cancelChildHide();
    });
    childPanel.addEventListener("focusin", function () {
      cancelHide();
      cancelChildHide();
    });
    childPanel.addEventListener("mouseleave", function (ev) {
      if (previewUtils.pointerWithinPanel(childPanel, ev)) return;
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, childActiveTrigger, childPanel)) return;
      scheduleChildHide();
    });
    childPanel.addEventListener("focusout", function (ev) {
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, childActiveTrigger, childPanel)) return;
      scheduleChildHide();
    });
    window.addEventListener("resize", function () {
      if (behavior.isAnchored && activeTrigger && !panel.hidden) {
        previewUtils.positionAnchoredPanel(panel, activeTrigger, 12, 10);
      } else if (behavior.isDocked && activeHost && !panel.hidden) {
        positionDockedPanel(activeHost);
      }
      if (childActiveTrigger && !childPanel.hidden) {
        previewUtils.positionAnchoredPanel(childPanel, childActiveTrigger, 12, 10);
      }
    });
    window.addEventListener("scroll", function () {
      if (behavior.isAnchored && activeTrigger && !panel.hidden) {
        previewUtils.positionAnchoredPanel(panel, activeTrigger, 12, 10);
      } else if (behavior.isDocked && activeHost && !panel.hidden) {
        positionDockedPanel(activeHost);
      }
      if (childActiveTrigger && !childPanel.hidden) {
        previewUtils.positionAnchoredPanel(childPanel, childActiveTrigger, 12, 10);
      }
    }, true);

    previewUtils.registerPreviewHydrator("inline", refresh);

    refresh(document);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bindInlinePreview);
  } else {
    bindInlinePreview();
  }
})();"##

def withBlueprintCssAssets (extras : List String := []) : List String :=
  [blueprintTokensCss] ++ extras

def withPreviewPanelCssAssets (extras : List String := []) : List String :=
  withBlueprintCssAssets ([previewPanelCss] ++ extras)

def withInlinePreviewCssAssets (extras : List String := []) : List String :=
  withBlueprintCssAssets (extras ++ [inlinePreviewCss])

def withPreviewPanelInlinePreviewCssAssets (extras : List String := []) : List String :=
  withPreviewPanelCssAssets (extras ++ [inlinePreviewCss])

def previewRuntimeJsAssets : List String :=
  [previewHoverUtilsJs]

def inlinePreviewJsAssets : List String :=
  previewRuntimeJsAssets ++ [inlineLinkPreviewJs]

def withPreviewRuntimeJsAssets (before : List String) (after : List String) : List String :=
  before ++ previewRuntimeJsAssets ++ after

def withInlinePreviewJsAssets (before : List String) (after : List String) : List String :=
  before ++ inlinePreviewJsAssets ++ after

end Informal.Commands
