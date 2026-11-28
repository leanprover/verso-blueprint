import { escapeHtml, normalizePanelBehavior, normalizePreviewMode, normalizePreviewPlacement, readElementOption, readFunctionOption, readNumberOption, readObjectOption, readStringOption } from "./preview-runtime-base.mjs";
import { renderHtmlInto, resolveBlueprintPreview } from "./preview-runtime-render.mjs";
import { bindCloseOnce, bindDismissHandlers, bindPanelRepositioner, bindPreviewTriggers, placeAnchoredPanel, readAnchorRect, shouldKeepOpen } from "./preview-runtime-lifecycle.mjs";

  /**
   * @typedef {Object} PreviewTriggerLifecycle
   * @property {() => void} cancelHide
   * @property {() => void} scheduleHide
   * @property {() => void} hide
   * @property {() => object} behavior
   * @property {(root?: unknown) => void} refresh
   * @property {(trigger: unknown, ev?: unknown, force?: unknown) => void} showTrigger
   */

  /**
   * @typedef {Object} PreviewRepositionLifecycle
   * @property {() => void} reposition
   */

  /**
   * @typedef {Object} PreviewDismissLifecycle
   * @property {unknown} root
   * @property {unknown} trigger
   * @property {unknown} panel
   * @property {unknown} closeButton
   * @property {() => boolean} isOpen
   * @property {(...args: unknown[]) => void} open
   * @property {(...args: unknown[]) => void} close
   * @property {(...args: unknown[]) => void} toggle
   */

  /**
   * @typedef {Object} PreviewSurface
   * @property {HTMLElement} panel
   * @property {HTMLElement | null} eyebrow
   * @property {Element} title
   * @property {HTMLElement | null} headerLabel
   * @property {Element} body
   * @property {HTMLElement | null} footer
   * @property {HTMLElement | null} closeButton
   * @property {object} behavior
   * @property {PreviewTriggerLifecycle | null} triggerLifecycle
   * @property {PreviewRepositionLifecycle | null} repositionLifecycle
   * @property {PreviewDismissLifecycle | null} dismissLifecycle
   * @property {() => boolean} isOpen
   * @property {(nextBehavior: unknown) => object} setBehavior
   * @property {(sourceNode: unknown) => void} setSource
   * @property {(sourceNode: unknown) => void} setFooterSource
   * @property {() => void} clearChrome
   * @property {() => void} hideContent
   * @property {(content: unknown) => boolean} showContent
   * @property {(content: unknown) => void} replaceBody
   * @property {(anchor?: unknown, nextBehavior?: unknown) => void} position
   * @property {() => void} hide
   * @property {(ev: unknown) => boolean} pointerWithin
   * @property {(nextTarget: unknown, trigger: unknown) => boolean} shouldKeepOpen
   * @property {(heading: string, payload: unknown, anchor?: unknown) => boolean} show
   * @property {(triggerOptions: unknown) => PreviewTriggerLifecycle} bindTriggers
   * @property {(repositionOptions: unknown) => PreviewRepositionLifecycle | null} bindRepositioner
   * @property {(dismissOptions: unknown) => PreviewDismissLifecycle} bindDismissal
   */

  // Bundled preview surface, panel, and content helpers.
  //
  // These helpers own panel slots, behavior state, content updates,
  // and runtime diagnostic markup for bundled clients.

  export function resetPanelPosition(panel) {
    placeAnchoredPanel(panel, null);
  }

  export function hidePreviewSurfaces(root) {
    const scope = root instanceof Element || root instanceof Document ? root : document;
    const selector = ".bp_preview_panel";
    const hidePanel = function (panel) {
      if (!(panel instanceof HTMLElement)) return;
      panel.hidden = true;
      resetPanelPosition(panel);
    };
    if (scope instanceof Element && scope.matches(selector)) {
      hidePanel(scope);
    }
    scope.querySelectorAll(selector).forEach(hidePanel);
  }

  export function configureCloseButton(closeButton, onClose, behavior) {
    if (!(closeButton instanceof HTMLElement)) return;
    const pinned = !!(behavior && behavior.isPinned);
    closeButton.hidden = !pinned;
    closeButton.style.display = pinned ? "" : "none";
    closeButton.setAttribute("aria-hidden", pinned ? "false" : "true");
    closeButton.tabIndex = pinned ? 0 : -1;
    if (!pinned) return;
    bindCloseOnce(closeButton, onClose);
  }

  export function pointerWithinPanel(panel, ev) {
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

  export function readPanelSlot(panel, selector) {
    if (!(panel instanceof Element)) return null;
    if (typeof selector !== "string" || selector.length === 0) return null;
    const node = panel.querySelector(selector);
    return node instanceof Element ? node : null;
  }

  /**
   * Class names of the shared preview panel shell. Every Blueprint popup is built
   * from this one shell, so styling and slot lookup have a single source.
   */
  export const previewPanelSlotClasses = Object.freeze({
    header: "bp_preview_panel_header",
    heading: "bp_preview_panel_heading",
    eyebrow: "bp_preview_panel_eyebrow",
    titleLine: "bp_preview_panel_titleline",
    status: "bp_preview_panel_status",
    title: "bp_preview_panel_title",
    label: "bp_preview_panel_label",
    close: "bp_preview_panel_close",
    body: "bp_preview_panel_body",
    footer: "bp_preview_panel_footer"
  });

  function slotSelector(slot) {
    return "." + previewPanelSlotClasses[slot];
  }

  export function readPreviewSurfaceSlots(panel, options) {
    const opts = options && typeof options === "object" ? options : {};
    const slot = function (name, optionName) {
      return readPanelSlot(panel, readStringOption(opts, optionName, slotSelector(name)));
    };
    return {
      panel: panel instanceof Element ? panel : null,
      eyebrow: slot("eyebrow", "eyebrowSelector"),
      status: slot("status", "statusSelector"),
      title: slot("title", "titleSelector"),
      headerLabel: slot("label", "headerLabelSelector"),
      body: slot("body", "bodySelector"),
      footer: slot("footer", "footerSelector"),
      closeButton: slot("close", "closeSelector")
    };
  }

  export function createPreviewSurface(options) {
    const opts = options && typeof options === "object" ? options : {};
    const panel = readElementOption(opts, "panel", null);
    if (!(panel instanceof HTMLElement)) return null;
    const slots = readPreviewSurfaceSlots(panel, opts);
    const titleSlot = slots.title;
    const bodySlot = slots.body;
    if (!(titleSlot instanceof Element) || !(bodySlot instanceof Element)) return null;
    const titleElement = titleSlot;
    const bodyElement = bodySlot;
    const headerLabelSlot = slots.headerLabel instanceof HTMLElement ? slots.headerLabel : null;
    const footerSlot = slots.footer instanceof HTMLElement ? slots.footer : null;
    const closeButtonSlot = slots.closeButton instanceof HTMLElement ? slots.closeButton : null;

    const defaults = readObjectOption(opts, "defaults", {});
    const margin = readNumberOption(opts, "margin", 12);
    const offset = readNumberOption(opts, "offset", 10);
    const side = readStringOption(opts, "side", "below");
    const footerHtmlAttr = readStringOption(opts, "footerHtmlAttr", "");
    const eyebrowSlot = slots.eyebrow instanceof HTMLElement ? slots.eyebrow : null;
    const defaultEyebrow = readStringOption(
      opts,
      "eyebrow",
      eyebrowSlot ? (eyebrowSlot.textContent || "").trim() : ""
    );
    const renderFooter = readFunctionOption(opts, "renderFooter", null);
    const onClose = readFunctionOption(opts, "onClose", null);
    const clearBody = readFunctionOption(opts, "clearBody", function (body) {
      body.replaceChildren();
    });
    const renderBody = readFunctionOption(opts, "renderBody", null);
    const positionPanel = readFunctionOption(opts, "positionPanel", null);
    const onHide = readFunctionOption(opts, "onHide", null);
    /** @type {PreviewTriggerLifecycle | null} */
    let triggerLifecycle = null;
    /** @type {PreviewRepositionLifecycle | null} */
    let repositionLifecycle = null;
    /** @type {PreviewDismissLifecycle | null} */
    let dismissLifecycle = null;

    function renderSurfaceBody(content) {
      const payload = /** @type {Record<string, unknown>} */ (
        content && typeof content === "object" ? content : {}
      );
      if (renderBody) {
        const bodyPayload = Object.prototype.hasOwnProperty.call(payload, "payload")
          ? payload.payload
          : payload.html;
        renderBody(bodyElement, bodyPayload, surface, payload);
        return true;
      }
      const html = typeof payload.html === "string" ? payload.html : "";
      if (html.length === 0 && payload.allowEmpty !== true) return false;
      renderHtmlInto(bodyElement, html, readObjectOption(payload, "renderOptions", undefined));
      return true;
    }

    function renderSurfaceTitle(content) {
      const payload = content && typeof content === "object" ? content : {};
      const heading = typeof payload.heading === "string" ? payload.heading : "";
      const href = typeof payload.headingHref === "string" ? payload.headingHref.trim() : "";
      const title = typeof payload.headingTitle === "string" ? payload.headingTitle.trim() : "";
      if (href.length === 0 || heading.length === 0) {
        titleElement.textContent = heading;
        return;
      }
      const link = document.createElement("a");
      link.setAttribute("href", href);
      if (title.length > 0) link.setAttribute("title", title);
      link.textContent = heading;
      titleElement.replaceChildren(link);
    }

    /** @type {PreviewSurface} */
    const surface = {
      panel: panel,
      eyebrow: eyebrowSlot,
      title: titleElement,
      headerLabel: headerLabelSlot,
      body: bodyElement,
      footer: footerSlot,
      closeButton: closeButtonSlot,
      behavior: normalizePanelBehavior(panel, defaults, null),
      triggerLifecycle: /** @type {typeof triggerLifecycle} */ (null),
      repositionLifecycle: /** @type {typeof repositionLifecycle} */ (null),
      dismissLifecycle: /** @type {typeof dismissLifecycle} */ (null),
      isOpen: function () {
        return !panel.hidden;
      },
      setBehavior: function (nextBehavior) {
        const behavior = normalizePanelBehavior(panel, defaults, nextBehavior);
        surface.behavior = behavior;
        panel.setAttribute("data-bp-preview-mode", behavior.mode);
        panel.setAttribute("data-bp-preview-placement", behavior.placement);
        configureCloseButton(slots.closeButton, function (ev) {
          if (onClose) {
            onClose(surface, ev);
          } else {
            surface.hideContent();
          }
        }, behavior);
        return behavior;
      },
      setSource: function (sourceNode) {
        setPreviewEyebrow(eyebrowSlot, sourceNode, defaultEyebrow);
        setPreviewStatus(slots.status, sourceNode);
        setPreviewHeaderLink(slots.headerLabel, sourceNode);
        surface.setFooterSource(sourceNode);
      },
      setFooterSource: function (sourceNode) {
        if (!(slots.footer instanceof HTMLElement)) return;
        const footerSlot = slots.footer;
        if (renderFooter) {
          renderFooter(footerSlot, sourceNode, surface);
          return;
        }
        if (!footerHtmlAttr) return;
        const footerHtml =
          sourceNode instanceof Element
            ? (sourceNode.getAttribute(footerHtmlAttr) || "").trim()
            : "";
        if (footerHtml.length > 0) {
          renderHtmlInto(footerSlot, footerHtml);
          footerSlot.hidden = false;
        } else {
          footerSlot.replaceChildren();
          footerSlot.hidden = true;
        }
      },
      clearChrome: function () {
        setPreviewEyebrow(eyebrowSlot, null, defaultEyebrow);
        setPreviewStatus(slots.status, null);
        setPreviewHeaderLink(slots.headerLabel, null);
        surface.setFooterSource(null);
      },
      hideContent: function () {
        panel.hidden = true;
        titleElement.textContent = "";
        clearBody(bodyElement);
        surface.clearChrome();
        if (onHide) onHide(surface);
      },
      showContent: function (content) {
        const payload = /** @type {Record<string, unknown>} */ (
          content && typeof content === "object" ? content : {}
        );
        const behavior =
          payload.behavior && typeof payload.behavior === "object"
            ? surface.setBehavior(payload.behavior)
            : surface.behavior;
        const source = payload.source instanceof Element ? payload.source : payload.anchor;
        if (!renderBody && typeof payload.html !== "string") {
          surface.hideContent();
          return false;
        }
        const html = typeof payload.html === "string" ? payload.html : "";
        if (!renderBody && html.length === 0 && payload.allowEmpty !== true) {
          surface.hideContent();
          return false;
        }
        renderSurfaceTitle(payload);
        surface.setSource(source);
        if (!renderSurfaceBody(payload)) {
          surface.hideContent();
          return false;
        }
        panel.hidden = false;
        surface.position(payload.anchor, behavior);
        return true;
      },
      replaceBody: function (content) {
        const payload = /** @type {Record<string, unknown>} */ (
          content && typeof content === "object" ? content : {}
        );
        if (payload.behavior && typeof payload.behavior === "object") {
          surface.setBehavior(payload.behavior);
        }
        renderSurfaceTitle(payload);
        if (
          Object.prototype.hasOwnProperty.call(payload, "source") ||
          Object.prototype.hasOwnProperty.call(payload, "anchor")
        ) {
          surface.setSource(payload.source instanceof Element ? payload.source : payload.anchor);
        }
        renderSurfaceBody(Object.assign({ allowEmpty: true }, payload));
        panel.hidden = false;
      },
      position: function (anchor, nextBehavior) {
        const behavior = normalizePanelBehavior(panel, defaults, nextBehavior || surface.behavior);
        if (positionPanel) {
          positionPanel(panel, anchor, surface);
        } else if (behavior && behavior.isAnchored && readAnchorRect(anchor)) {
          placeAnchoredPanel(panel, anchor, { side: side, margin: margin, offset: offset });
        } else {
          resetPanelPosition(panel);
        }
      },
      hide: function () {
        surface.hideContent();
      },
      pointerWithin: function (ev) {
        return pointerWithinPanel(panel, ev);
      },
      shouldKeepOpen: function (nextTarget, trigger) {
        return shouldKeepOpen(nextTarget, trigger, panel);
      },
      show: function (heading, payload, anchor) {
        const content = {
          heading: typeof heading === "string" ? heading : "",
          anchor: anchor
        };
        if (typeof payload === "string") {
          content.html = payload;
        } else {
          content.payload = payload;
        }
        return surface.showContent(content);
      },
      bindTriggers: function (triggerOptions) {
        const triggerOpts = /** @type {Record<string, unknown>} */ (
          triggerOptions && typeof triggerOptions === "object" ? Object.assign({}, triggerOptions) : {}
        );
        if (!(triggerOpts.panel instanceof Element)) triggerOpts.panel = panel;
        if (
          typeof triggerOpts.getBehavior !== "function" &&
          !(triggerOpts.behavior && typeof triggerOpts.behavior === "object")
        ) {
          triggerOpts.getBehavior = function () { return surface.behavior; };
        }
        if (typeof triggerOpts.position !== "function") {
          triggerOpts.position = function (anchor) { surface.position(anchor); };
        }
        triggerLifecycle = bindPreviewTriggers(triggerOpts);
        surface.triggerLifecycle = triggerLifecycle;
        return triggerLifecycle;
      },
      bindRepositioner: function (repositionOptions) {
        const repositionOpts = /** @type {Record<string, unknown>} */ (
          repositionOptions && typeof repositionOptions === "object"
            ? Object.assign({}, repositionOptions)
            : {}
        );
        if (!(repositionOpts.owner instanceof Element)) repositionOpts.owner = panel;
        repositionLifecycle = bindPanelRepositioner(repositionOpts);
        surface.repositionLifecycle = repositionLifecycle;
        return repositionLifecycle;
      },
      bindDismissal: function (dismissOptions) {
        const dismissOpts = /** @type {Record<string, unknown>} */ (
          dismissOptions && typeof dismissOptions === "object" ? Object.assign({}, dismissOptions) : {}
        );
        if (!(dismissOpts.panel instanceof Element)) dismissOpts.panel = panel;
        if (
          !Object.prototype.hasOwnProperty.call(dismissOpts, "closeButton") &&
          slots.closeButton instanceof Element
        ) {
          dismissOpts.closeButton = slots.closeButton;
        }
        dismissLifecycle = bindDismissHandlers(dismissOpts);
        surface.dismissLifecycle = dismissLifecycle;
        return dismissLifecycle;
      }
    };

    surface.setBehavior(surface.behavior);
    return surface;
  }

  export function previewResultTitle(result) {
    const entry =
      result && result.manifestEntry && typeof result.manifestEntry === "object"
        ? result.manifestEntry
        : null;
    const title = entry && typeof entry.title === "string" ? entry.title.trim() : "";
    return title;
  }

  export async function renderPreviewIntoSurface(surface, previewKey, options) {
    if (!surface || typeof surface.replaceBody !== "function") {
      throw new Error("renderPreviewIntoSurface surface must be a preview surface");
    }
    const opts = options && typeof options === "object" ? options : {};
    const heading = readStringOption(
      opts,
      "heading",
      surface.title instanceof Element ? (surface.title.textContent || "") : ""
    );
    const loadingHtml = readStringOption(opts, "loadingHtml", "");
    const renderOptions = readObjectOption(opts, "renderOptions", {});
    const loadingRenderOptions =
      readObjectOption(opts, "loadingRenderOptions", { hydrate: false, renderMath: false });
    const diagnosticRenderOptions =
      readObjectOption(opts, "diagnosticRenderOptions", { hydrate: false, renderMath: false });
    const shouldRender = readFunctionOption(opts, "shouldRender", null);
    const mayRender = function () {
      return !shouldRender || shouldRender();
    };
    const replaceBody = function (html, bodyRenderOptions, bodyHeading) {
      if (!mayRender()) return false;
      surface.replaceBody({
        heading: typeof bodyHeading === "string" && bodyHeading.trim().length > 0
          ? bodyHeading.trim()
          : heading,
        html: html,
        allowEmpty: true,
        renderOptions: bodyRenderOptions
      });
      return true;
    };
    const fallbackDiagnostic = function (optionName, fallbackDetail) {
      const messageOptions = readObjectOption(opts, optionName, {});
      return previewMessageHtml(Object.assign({
        kind: "error",
        title: "Preview unavailable",
        detail: fallbackDetail
      }, messageOptions));
    };

    if (loadingHtml.length > 0) {
      replaceBody(loadingHtml, loadingRenderOptions);
    }
    try {
      const result = await resolveBlueprintPreview(previewKey, opts);
      if (!mayRender()) return result;
      if (!result || !result.ok) {
        const diagnosticHtml = result && typeof result.diagnosticHtml === "string"
          ? result.diagnosticHtml
          : "";
        const resultTitle = previewResultTitle(result);
        const semanticOnlyDiagnostic =
          result && result.reason === "semantic-preview-body-missing"
            ? fallbackDiagnostic(
                "semanticOnlyDiagnostic",
                "This preview target does not have a rendered preview entry."
              )
            : "";
        replaceBody(
          semanticOnlyDiagnostic ||
            diagnosticHtml ||
            fallbackDiagnostic("fallbackDiagnostic", "The preview cache content could not be loaded."),
          diagnosticRenderOptions,
          resultTitle
        );
        return result;
      }
      replaceBody(result.html, renderOptions, previewResultTitle(result));
      return result;
    } catch (_err) {
      replaceBody(
        fallbackDiagnostic(
          "exceptionDiagnostic",
          "The preview cache content could not be loaded. Refresh the page, or rebuild the site if this persists."
        ),
        diagnosticRenderOptions
      );
      return null;
    }
  }

  export async function resolvePreviewHtml(previewKey, options) {
    const opts = options && typeof options === "object" ? options : {};
    try {
      const result = await resolveBlueprintPreview(previewKey, opts);
      if (result && result.ok && typeof result.html === "string" && result.html.length > 0) {
        return {
          ok: true,
          key: result.key,
          html: result.html,
          result: result
        };
      }
      return {
        ok: false,
        key: result && typeof result.key === "string" ? result.key : previewKey,
        reason: result && typeof result.reason === "string" ? result.reason : "",
        html: result && typeof result.diagnosticHtml === "string" ? result.diagnosticHtml : "",
        result: result || null
      };
    } catch (_err) {
      return {
        ok: false,
        key: previewKey,
        reason: "preview-load-failed",
        html: previewMessageHtml({
          kind: "error",
          title: "Preview unavailable",
          detail: "The preview cache content could not be loaded. Refresh the page, or rebuild the site if this persists."
        }),
        result: null
      };
    }
  }

  function closeIcon(doc) {
    const ns = "http://www.w3.org/2000/svg";
    const svg = doc.createElementNS(ns, "svg");
    svg.setAttribute("viewBox", "0 0 16 16");
    svg.setAttribute("width", "16");
    svg.setAttribute("height", "16");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    const path = doc.createElementNS(ns, "path");
    path.setAttribute("d", "M4 4l8 8M12 4l-8 8");
    svg.appendChild(path);
    return svg;
  }

  /**
   * Build the shared preview panel shell: a header with an optional eyebrow (what
   * kind of popup this is), a title and label link, and a close button; a body; and
   * an optional footer. `roleClass` names the popup's role for sizing and placement.
   */
  export function createPreviewPanel(options) {
    const opts = options && typeof options === "object" ? options : {};
    const doc = opts.document && typeof opts.document.createElement === "function"
      ? opts.document
      : document;
    const id = readStringOption(opts, "id", "");
    const roleClass = readStringOption(opts, "roleClass", "");
    const eyebrowText = readStringOption(opts, "eyebrow", "");
    const closeLabel = readStringOption(opts, "closeLabel", "Close preview");
    const parent = opts.parent instanceof Element ? opts.parent : doc.body;
    const element = function (tag, slot) {
      const node = doc.createElement(tag);
      node.className = previewPanelSlotClasses[slot];
      return node;
    };

    const panel = doc.createElement("aside");
    if (id.length > 0) panel.id = id;
    panel.className = "bp_preview_panel" + (roleClass.length > 0 ? " " + roleClass : "");
    panel.setAttribute("data-bp-preview-mode", normalizePreviewMode(opts.mode, "hover"));
    panel.setAttribute("data-bp-preview-placement", normalizePreviewPlacement(opts.placement, "anchored"));
    panel.hidden = true;

    const header = element("div", "header");
    const heading = element("div", "heading");
    const eyebrow = element("div", "eyebrow");
    eyebrow.textContent = eyebrowText;
    eyebrow.hidden = eyebrowText.length === 0;
    const titleLine = element("div", "titleLine");
    const status = element("span", "status");
    status.hidden = true;
    status.setAttribute("aria-hidden", "true");
    titleLine.appendChild(status);
    titleLine.appendChild(element("div", "title"));
    const label = element("a", "label");
    label.hidden = true;
    titleLine.appendChild(label);
    heading.appendChild(eyebrow);
    heading.appendChild(titleLine);
    const close = element("button", "close");
    close.type = "button";
    close.setAttribute("aria-label", closeLabel);
    close.appendChild(closeIcon(doc));
    header.appendChild(heading);
    header.appendChild(close);
    panel.appendChild(header);
    panel.appendChild(element("div", "body"));
    const footer = element("div", "footer");
    footer.hidden = true;
    panel.appendChild(footer);

    if (opts.append !== false && parent instanceof Element) {
      parent.appendChild(panel);
    }
    return panel;
  }

  export function previewMessageHtml(options) {
    const opts = options && typeof options === "object" ? options : {};
    const rootClass = readStringOption(opts, "rootClass", "bp_preview_message");
    const titleClass = readStringOption(opts, "titleClass", "bp_preview_message_title");
    const detailClass = readStringOption(opts, "detailClass", "bp_preview_message_detail");
    const kindAttr = readStringOption(opts, "kindAttr", "data-bp-preview-message");
    const kind = readStringOption(opts, "kind", "info");
    const title = readStringOption(opts, "title", "Preview unavailable");
    const detail = typeof opts.detail === "string" ? opts.detail : "";
    let html =
      '<div class="' +
      escapeHtml(rootClass) +
      '" ' +
      escapeHtml(kindAttr) +
      '="' +
      escapeHtml(kind) +
      '">';
    html += '<div class="' + escapeHtml(titleClass) + '">' + escapeHtml(title) + "</div>";
    if (detail.length > 0) {
      html += '<div class="' + escapeHtml(detailClass) + '">' + escapeHtml(detail) + "</div>";
    }
    html += "</div>";
    return html;
  }

  export function setPreviewEyebrow(eyebrowNode, sourceNode, fallback) {
    if (!(eyebrowNode instanceof HTMLElement)) return;
    const fromSource =
      sourceNode instanceof Element
        ? (sourceNode.getAttribute("data-bp-preview-eyebrow") || "").trim()
        : "";
    const text = fromSource || (typeof fallback === "string" ? fallback : "");
    eyebrowNode.textContent = text;
    eyebrowNode.hidden = text.length === 0;
  }

  /**
   * Show the previewed block's status mark before the title, from the source's
   * `data-bp-preview-status-symbol` and `data-bp-preview-status-class` (the suffix
   * of the heading's `bp_code_link_status_*` class, so the mark looks the same).
   */
  export function setPreviewStatus(statusNode, sourceNode) {
    if (!(statusNode instanceof HTMLElement)) return;
    const read = function (name) {
      return sourceNode instanceof Element ? (sourceNode.getAttribute(name) || "").trim() : "";
    };
    const symbol = read("data-bp-preview-status-symbol");
    const suffix = read("data-bp-preview-status-class");
    statusNode.className = previewPanelSlotClasses.status +
      (symbol && suffix ? " bp_code_link_status_" + suffix : "");
    statusNode.replaceChildren();
    if (symbol) {
      const mark = document.createElement("span");
      mark.className = "bp_code_status_symbol";
      mark.textContent = symbol;
      statusNode.appendChild(mark);
    }
    statusNode.hidden = symbol.length === 0;
  }

  export function setPreviewHeaderLink(labelNode, sourceNode) {
    if (!(labelNode instanceof HTMLElement)) return;
    const label =
      sourceNode instanceof Element
        ? (sourceNode.getAttribute("data-bp-preview-header-label") || "").trim()
        : "";
    const href =
      sourceNode instanceof Element
        ? (sourceNode.getAttribute("data-bp-preview-header-href") || "").trim()
        : "";
    if (label.length > 0) {
      labelNode.textContent = label;
      if (href.length > 0) {
        labelNode.setAttribute("href", href);
      } else {
        labelNode.removeAttribute("href");
      }
      labelNode.hidden = false;
    } else {
      labelNode.textContent = "";
      labelNode.removeAttribute("href");
      labelNode.hidden = true;
    }
  }

  export const previewRuntimeSurface = {
    resetPanelPosition,
    hidePreviewSurfaces,
    configureCloseButton,
    pointerWithinPanel,
    readPanelSlot,
    readPreviewSurfaceSlots,
    createPreviewSurface,
    renderPreviewIntoSurface,
    resolvePreviewHtml,
    createPreviewPanel,
    previewMessageHtml,
    previewResultTitle,
    previewPanelSlotClasses,
    setPreviewEyebrow,
    setPreviewStatus,
    setPreviewHeaderLink
  };

export default previewRuntimeSurface;
