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

  function relationBadgeSpec(code) {
    switch (code) {
      case "s":
        return {
          className: "bp_relation_axis_badge bp_relation_badge_axis bp_relation_badge_statement",
          title: "Declared in the statement",
          text: "statement"
        };
      case "p":
        return {
          className: "bp_relation_axis_badge bp_relation_badge_axis bp_relation_badge_proof",
          title: "Declared in the proof",
          text: "proof"
        };
      case "oa":
        return {
          className: "bp_relation_axis_badge bp_relation_badge_origin bp_relation_badge_origin_automatic",
          title: "Origin: automatic",
          text: "automatic"
        };
      case "ia":
        return {
          className: "bp_relation_axis_badge bp_relation_badge_intent bp_relation_badge_intent_auxiliary",
          title: "Intent: auxiliary",
          text: "auxiliary"
        };
      case "it":
        return {
          className: "bp_relation_axis_badge bp_relation_badge_intent bp_relation_badge_intent_technical",
          title: "Intent: technical",
          text: "technical"
        };
      default:
        return null;
    }
  }

  function appendRelationBadge(parent, code) {
    const spec = relationBadgeSpec(code);
    if (!spec) return;
    const badge = document.createElement("span");
    badge.className = spec.className;
    badge.title = spec.title;
    badge.textContent = spec.text;
    parent.appendChild(badge);
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
    const list = panel.querySelector(".bp_relation_list");
    const items = [];
    let hydratedItems = false;
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

    function relationEntryData() {
      if (!(list instanceof Element)) return [];
      const dataScript = list.querySelector("script.bp-relation-entries");
      const rawData = dataScript ? (dataScript.textContent || "").trim() : "";
      if (!rawData) return [];
      try {
        const parsed = JSON.parse(rawData);
        return Array.isArray(parsed) ? parsed : [];
      } catch (_err) {
        return [];
      }
    }

    // Must match RelatedPanel.panelEntryDataJson; kept positional because large
    // blueprints can have thousands of relation rows.
    function createRelationItem(entry) {
      if (!Array.isArray(entry)) return null;
      const title = typeof entry[0] === "string" && entry[0] ? entry[0] : defaultTitle;
      const previewKey = typeof entry[1] === "string" ? entry[1] : "";
      const label = typeof entry[2] === "string" ? entry[2] : "";
      const href = typeof entry[3] === "string" ? entry[3] : "";
      const badgeCodes = Array.isArray(entry[4]) ? entry[4] : [];
      const active = entry[5] === true;
      const item = document.createElement("li");
      item.className = active ? "bp_relation_item bp_relation_item_active" : "bp_relation_item";
      item.setAttribute("data-bp-relation-preview-title", title);
      if (previewKey) item.setAttribute("data-bp-relation-preview-key", previewKey);
      if (label) item.setAttribute("data-bp-preview-header-label", label);
      if (href) item.setAttribute("data-bp-preview-header-href", href);

      const target = document.createElement(href ? "a" : "span");
      target.className = "bp_relation_target";
      if (href) target.setAttribute("href", href);

      const titleNode = document.createElement("span");
      titleNode.className = "bp_relation_target_title";
      titleNode.textContent = title;
      target.appendChild(titleNode);

      const meta = document.createElement("span");
      meta.className = "bp_relation_target_meta";
      const code = document.createElement("code");
      code.textContent = label;
      meta.appendChild(code);
      badgeCodes.forEach(function (badgeCode) {
        if (typeof badgeCode === "string") appendRelationBadge(meta, badgeCode);
      });
      target.appendChild(meta);
      item.appendChild(target);
      return item;
    }

    function bindRelationItem(item) {
      if (!(item instanceof Element)) return;
      item.addEventListener("mouseenter", function () {
        activate(item);
      });
      item.addEventListener("focusin", function () {
        activate(item);
      });
    }

    function ensureItems() {
      if (hydratedItems) return items;
      hydratedItems = true;
      if (!(list instanceof Element)) return items;
      const fragment = document.createDocumentFragment();
      const entryData = relationEntryData();
      entryData.forEach(function (entry) {
        const item = createRelationItem(entry);
        if (item instanceof Element) {
          bindRelationItem(item);
          items.push(item);
          fragment.appendChild(item);
        }
      });
      const dataScript = list.querySelector("script.bp-relation-entries");
      if (dataScript instanceof Element) dataScript.remove();
      list.appendChild(fragment);
      if (!items.some(function (item) {
        return item instanceof Element && item.classList.contains("bp_relation_item_active");
      }) && items[0] instanceof Element) {
        items[0].classList.add("bp_relation_item_active");
      }
      return items;
    }

    function activeItem() {
      const currentItems = ensureItems();
      return currentItems.find(function (item) {
        return item instanceof Element && item.classList.contains("bp_relation_item_active");
      }) || currentItems[0] || null;
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
