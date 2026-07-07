import { collectPreviewTemplates, readElementOption, readFunctionOption, readHtml, readNumberOption, readObjectOption, readRootOption, readStringOption } from "./preview-runtime-base.mjs";
import { setTemplatePreviewDescriptorBinder } from "./preview-runtime-hydration.mjs";
import { createPreviewSurface, previewResultTitle, resolvePreviewHtml } from "./preview-runtime-surface.mjs";

  // Template preview binding adapts the shared helpers to concrete surfaces.

  export function bindTemplatePreview(options) {
    const opts = options && typeof options === "object" ? options : {};
    const root = readRootOption(opts, "root", document);
    const previewRoot = readRootOption(opts, "previewRoot", root);
    const triggerRoot = readRootOption(opts, "triggerRoot", root);
    const panel = readElementOption(opts, "panel", null);
    const templateSelector = readStringOption(opts, "templateSelector", "");
    const triggerSelector = readStringOption(opts, "triggerSelector", "");
    const keyAttr = readStringOption(opts, "keyAttr", "data-bp-preview-label");
    const titleAttr = readStringOption(opts, "titleAttr", keyAttr);
    const titleSelector = readStringOption(opts, "titleSelector", "");
    const bodySelector = readStringOption(opts, "bodySelector", "");
    const triggerBoundAttr = readStringOption(opts, "triggerBoundAttr", "data-bp-bound");
    const defaults = readObjectOption(opts, "defaults", {});
    const margin = readNumberOption(opts, "margin", 12);
    const offset = readNumberOption(opts, "offset", 10);
    const readKey = readFunctionOption(opts, "readKey", function (trigger) {
      if (!(trigger instanceof Element)) return "";
      return (trigger.getAttribute(keyAttr) || "").trim();
    });
    const readTitle = readFunctionOption(opts, "readTitle", function (trigger, key) {
      if (!(trigger instanceof Element)) return key;
      const heading = (trigger.getAttribute(titleAttr) || "").trim();
      return heading || key;
    });
    const readLookupKey = readFunctionOption(opts, "readLookupKey", function (trigger) {
      if (!(trigger instanceof Element)) return "";
      return (trigger.getAttribute("data-bp-preview-key") || "").trim();
    });
    const allowHtmlCache = !!opts.allowHtmlCache;

    const previewMap = collectPreviewTemplates(previewRoot, templateSelector, keyAttr);
    const triggers = triggerRoot.querySelectorAll(triggerSelector);
    if (panel && panel.ownerDocument && panel.ownerDocument.body && panel.parentElement !== panel.ownerDocument.body) {
      panel.ownerDocument.body.appendChild(panel);
    }
    const surface = createPreviewSurface({
      panel: panel,
      titleSelector: titleSelector,
      bodySelector: bodySelector,
      closeSelector: readStringOption(opts, "closeSelector", ""),
      defaults: defaults,
      margin: margin,
      offset: offset,
      onClose: function () { hidePanel(); }
    });
    if (!surface || (!allowHtmlCache && previewMap.size === 0)) {
      if (panel instanceof HTMLElement) panel.hidden = true;
      return null;
    }
    const previewSurface = surface;
    if (triggers.length === 0) {
      previewSurface.hide();
      return null;
    }
    let activeTrigger = null;
    let showRequestToken = 0;
    let triggerLifecycle = null;

    function hidePanel() {
      if (triggerLifecycle) triggerLifecycle.cancelHide();
      showRequestToken += 1;
      previewSurface.hide();
      activeTrigger = null;
    }

    async function resolveTriggerPreview(trigger, key) {
      if (!allowHtmlCache) {
        const localEntry = previewMap.get(key);
        return {
          html: readHtml(localEntry),
          title: ""
        };
      }
      const lookupKey = readLookupKey(trigger, key, null);
      const resolved = await resolvePreviewHtml(lookupKey, opts);
      if (resolved && resolved.ok) {
        return {
          html: resolved.html,
          title: previewResultTitle(resolved.result)
        };
      }
      const result = resolved ? resolved.result : null;
      const diagnosticHtml =
        result && typeof result.diagnosticHtml === "string" ? result.diagnosticHtml : "";
      const dataApi = opts.dataApi && typeof opts.dataApi === "object" ? opts.dataApi : null;
      const htmlCacheDiagnosticHtml =
        dataApi && typeof dataApi.htmlCacheDiagnosticHtml === "function"
          ? dataApi.htmlCacheDiagnosticHtml(lookupKey || key)
          : "";
      return {
        html: diagnosticHtml || htmlCacheDiagnosticHtml,
        title: previewResultTitle(result)
      };
    }

    async function showFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      const key = readKey(trigger);
      const requestToken = ++showRequestToken;
      const resolved = await resolveTriggerPreview(trigger, key);
      const html = resolved.html || "";
      if (requestToken !== showRequestToken) return;
      if (!key || !html) {
        hidePanel();
        return;
      }
      activeTrigger = trigger;
      const heading = resolved.title || readTitle(trigger, key);
      previewSurface.showContent({
        heading: heading,
        html: html,
        anchor: trigger
      });
    }

    triggerLifecycle = previewSurface.bindTriggers({
      triggerRoot: triggerRoot,
      triggerSelector: triggerSelector,
      triggerBoundAttr: triggerBoundAttr,
      show: showFromTrigger,
      hide: hidePanel,
      getActiveTrigger: function () { return activeTrigger; }
    });

    return {
      previewMap: previewMap,
      surface: previewSurface,
      behavior: previewSurface.behavior,
      hidePanel: hidePanel,
      showFromTrigger: showFromTrigger
    };
  }

  export function readTemplateDescriptorString(root, name, fallback) {
    if (!(root instanceof Element)) return fallback;
    const value = (root.getAttribute("data-bp-template-preview-" + name) || "").trim();
    return value.length > 0 ? value : fallback;
  }

  export function bindTemplatePreviewDescriptor(root, options) {
    const opts = options && typeof options === "object" ? options : {};
    if (!(root instanceof Element)) return null;
    if (root.getAttribute("data-bp-template-preview-bound") === "1") return null;

    const panelSelector = readTemplateDescriptorString(root, "panel-selector", "");
    const panel = panelSelector ? root.querySelector(panelSelector) : null;
    if (!(panel instanceof Element)) return null;

    const mode = readTemplateDescriptorString(root, "mode", "");
    const placement = readTemplateDescriptorString(root, "placement", "");
    const bindOptions = {
      root: root,
      previewRoot: root,
      triggerRoot: root,
      panel: panel,
      templateSelector: readTemplateDescriptorString(root, "template-selector", ""),
      triggerSelector: readTemplateDescriptorString(root, "trigger-selector", ""),
      keyAttr: readTemplateDescriptorString(root, "key-attr", "data-bp-preview-label"),
      titleAttr: readTemplateDescriptorString(root, "title-attr", ""),
      titleSelector: readTemplateDescriptorString(root, "title-selector", ""),
      bodySelector: readTemplateDescriptorString(root, "body-selector", ""),
      closeSelector: readTemplateDescriptorString(root, "close-selector", ""),
      triggerBoundAttr: readTemplateDescriptorString(root, "trigger-bound-attr", "data-bp-bound")
    };
    if ("fetchJson" in opts) bindOptions.fetchJson = opts.fetchJson;
    if ("dataApi" in opts) bindOptions.dataApi = opts.dataApi;
    if (mode.length > 0 || placement.length > 0) {
      bindOptions.defaults = {
        mode: mode.length > 0 ? mode : "hover",
        placement: placement.length > 0 ? placement : "anchored"
      };
    }
    if (root.getAttribute("data-bp-template-preview-allow-html-cache") === "true") {
      bindOptions.allowHtmlCache = true;
    }

    const controller = bindTemplatePreview(bindOptions);
    if (controller) {
      root.setAttribute("data-bp-template-preview-bound", "1");
    }
    return controller;
  }

  export function bindTemplatePreviewDescriptors(root, options) {
    const scope = root instanceof Element || root instanceof Document ? root : document;
    const selector = "[data-bp-template-preview-root]";
    const controllers = [];
    if (scope instanceof Element && scope.matches(selector)) {
      const controller = bindTemplatePreviewDescriptor(scope, options);
      if (controller) controllers.push(controller);
    }
    scope.querySelectorAll(selector).forEach(function (rootNode) {
      const controller = bindTemplatePreviewDescriptor(rootNode, options);
      if (controller) controllers.push(controller);
    });
    return controllers;
  }

  if (typeof setTemplatePreviewDescriptorBinder === "function") {
    setTemplatePreviewDescriptorBinder(bindTemplatePreviewDescriptors);
  }

  export const previewRuntimeTemplate = {
    bindTemplatePreview,
    readTemplateDescriptorString,
    bindTemplatePreviewDescriptor,
    bindTemplatePreviewDescriptors
  };

export default previewRuntimeTemplate;
