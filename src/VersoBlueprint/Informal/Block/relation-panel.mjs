  export function relationPreviewDiagnosticOptions(detail) {
    return {
      rootClass: "bp_relation_preview_message",
      titleClass: "bp_relation_preview_message_title",
      detailClass: "bp_relation_preview_message_detail",
      kind: "error",
      title: "Preview unavailable",
      detail: detail || "The preview cache content could not be loaded."
    };
  }

  export function bindRelationPanel(previewUtils, panel) {
    if (!(panel instanceof Element)) return;
    if (panel.getAttribute("data-bp-bound") === "1") return;
    panel.setAttribute("data-bp-bound", "1");

    const wrap = panel.closest(".bp_relation_wrap");
    const chip = wrap instanceof Element ? wrap.querySelector(".bp_relation_chip") : null;
    const surface = previewUtils.createPreviewSurface({
      panel: panel,
      titleSelector: ".bp_relation_preview_title",
      headerLabelSelector: ".bp_relation_preview_header_label",
      bodySelector: ".bp_relation_preview_body",
      defaults: { mode: "hover", placement: "anchored" }
    });
    if (!surface || !(surface.headerLabel instanceof Element)) return;

    const defaultTitle = (surface.title.textContent || "").trim() || "Relation preview";
    const initialLoadingHtml = (surface.body.innerHTML || "").trim();
    const items = Array.from(panel.querySelectorAll(".bp_relation_item[data-bp-relation-preview-id]"));
    let activateRequestToken = 0;
    let relationLifecycle = null;

    function setExpanded(expanded) {
      if (chip instanceof Element) {
        chip.setAttribute("aria-expanded", expanded ? "true" : "false");
      }
    }

    function cancelClose() {
      if (relationLifecycle) relationLifecycle.cancelHide();
    }

    function activeItem() {
      return items.find(function (item) {
        return item instanceof Element && item.classList.contains("bp_relation_item_active");
      }) || items[0] || null;
    }

    function selectItem(item) {
      if (!(item instanceof Element)) return;
      const itemTitle = (item.getAttribute("data-bp-relation-preview-title") || "").trim() || defaultTitle;
      items.forEach(function (other) {
        if (other instanceof Element) {
          other.classList.toggle("bp_relation_item_active", other === item);
        }
      });
      surface.replaceBody({
        heading: itemTitle,
        source: item,
        html: "",
        allowEmpty: true,
        renderOptions: { hydrate: false, renderMath: false }
      });
    }

    function loadActivePreview() {
      const item = activeItem();
      if (item instanceof Element) {
        activate(item, { openWrap: false });
      }
    }

    function openWrap(options) {
      const opts = options && typeof options === "object" ? options : {};
      cancelClose();
      if (wrap instanceof Element) {
        wrap.classList.add("bp_relation_wrap_open");
      }
      setExpanded(true);
      if (opts.loadPreview !== false) {
        loadActivePreview();
      }
    }

    function closeWrap() {
      cancelClose();
      if (wrap instanceof Element) {
        wrap.classList.remove("bp_relation_wrap_open");
      }
      setExpanded(false);
    }

    function wrapIsOpen() {
      return wrap instanceof Element && wrap.classList.contains("bp_relation_wrap_open");
    }

    async function activate(item, options) {
      if (!(item instanceof Element)) return;
      const opts = options && typeof options === "object" ? options : {};
      const itemTitle = (item.getAttribute("data-bp-relation-preview-title") || "").trim() || defaultTitle;
      const previewKey = (item.getAttribute("data-bp-relation-preview-key") || "").trim();
      const requestToken = ++activateRequestToken;
      selectItem(item);
      if (opts.openWrap !== false) {
        openWrap({ loadPreview: false });
      }
      if (!previewKey) {
        surface.replaceBody({
          heading: itemTitle,
          source: item,
          html: previewUtils.previewMessageHtml(relationPreviewDiagnosticOptions(
            "This relation target does not have a rendered preview entry."
          )),
          renderOptions: { hydrate: false, renderMath: false }
        });
        return;
      }
      await previewUtils.renderPreviewIntoSurface(surface, previewKey, {
        loadingHtml: initialLoadingHtml,
        renderOptions: {},
        loadingRenderOptions: { hydrate: false, renderMath: false },
        diagnosticRenderOptions: { hydrate: false, renderMath: false },
        shouldRender: function () {
          return requestToken === activateRequestToken;
        },
        fallbackDiagnostic: relationPreviewDiagnosticOptions(
          "The preview cache content could not be loaded."
        ),
        semanticOnlyDiagnostic: relationPreviewDiagnosticOptions(
          "This relation target does not have a rendered preview entry."
        ),
        exceptionDiagnostic: relationPreviewDiagnosticOptions(
          "The preview cache content could not be loaded. Refresh the page, or rebuild the site if this persists."
        )
      });
    }

    items.forEach(function (item) {
      if (!(item instanceof Element)) return;
      item.addEventListener("mouseenter", function () {
        activate(item);
      });
      item.addEventListener("focusin", function () {
        activate(item);
      });
    });
    const initialItem = items.find(function (item) {
      return item instanceof Element && item.classList.contains("bp_relation_item_active");
    }) || items[0];
    if (initialItem instanceof Element) {
      selectItem(initialItem);
    }

    if (wrap instanceof Element && chip instanceof Element) {
      setExpanded(wrap.classList.contains("bp_relation_wrap_open"));
      relationLifecycle = surface.bindTriggers({
        triggerRoot: wrap,
        triggerSelector: ".bp_relation_chip",
        triggerBoundAttr: "data-bp-relation-chip-bound",
        panelBoundAttr: "data-bp-relation-panel-lifetime-bound",
        show: function () { openWrap(); },
        hide: closeWrap,
        getActiveTrigger: function () { return chip; },
        shouldKeepOpen: function (_trigger, ev) {
          return surface.shouldKeepOpen(ev && ev.relatedTarget, wrap);
        },
        onPanelEnter: function () { openWrap(); },
        bindWindow: false
      });
      surface.bindDismissal({
        owner: wrap,
        root: wrap,
        trigger: chip,
        boundAttr: "data-bp-relation-dismiss-bound",
        isOpen: wrapIsOpen,
        close: closeWrap,
        toggle: function () {
          if (wrapIsOpen()) {
            closeWrap();
          } else {
            openWrap();
          }
        },
        stopPanelClick: true
      });
    }
  }

  export function bindAllRelationPanels(previewUtils, root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    root.querySelectorAll(".bp_relation_panel").forEach(function (panel) {
      bindRelationPanel(previewUtils, panel);
    });
  }

  export function startRelationPanels(previewUtils) {
    previewUtils.registerPreviewHydrator("relationPanel", function (root) {
      bindAllRelationPanels(previewUtils, root);
    });
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () {
        bindAllRelationPanels(previewUtils, document);
      });
    } else {
      bindAllRelationPanels(previewUtils, document);
    }
  }

  export const relationPanelRuntime = {
    relationPreviewDiagnosticOptions,
    bindRelationPanel,
    bindAllRelationPanels,
    startRelationPanels
  };

export default relationPanelRuntime;
