(function () {
  function debounce(fn, waitMs) {
    let timeout = null;
    return function () {
      const args = arguments;
      clearTimeout(timeout);
      timeout = setTimeout(function () {
        fn.apply(null, args);
      }, waitMs);
    };
  }

  function readViewportHeight() {
    return window.innerHeight || document.documentElement.clientHeight || 900;
  }

  function parsePixelSize(value) {
    const size = parseFloat(value);
    return isFinite(size) ? size : NaN;
  }

  function normalizeGraphDirection(rawDirection) {
    const direction = String(rawDirection || "").trim().toUpperCase();
    if (direction === "LR" || direction === "RL" || direction === "BT") {
      return direction;
    }
    return "TB";
  }

  function readGraphCanvasFlowBottom(graphRoot) {
    if (!(graphRoot instanceof Element)) return 0;
    const flowContainer = graphRoot.closest(".content-wrapper") || graphRoot.closest("main");
    if (!(flowContainer instanceof Element)) return 0;
    const rect = flowContainer.getBoundingClientRect();
    return rect.bottom;
  }

  function layoutGraphCanvas(graphRoot, graphState) {
    if (!(graphRoot instanceof Element)) return;
    const rect = graphRoot.getBoundingClientRect();
    const viewportHeight = readViewportHeight();
    const bottomGap = 20;
    const viewportMaxHeight = Math.max(280, Math.floor(viewportHeight * 0.84));
    const flowBottom = readGraphCanvasFlowBottom(graphRoot);
    const trailingHeight = Math.max(0, flowBottom - rect.bottom);
    const availableHeight = Math.max(1, Math.floor(viewportHeight - rect.top - bottomGap - trailingHeight));
    const autoHeight = Math.min(viewportMaxHeight, availableHeight);
    const minHeight = Math.min(autoHeight, 280);
    const currentHeight = parsePixelSize(graphRoot.style.height);
    const state = graphState && typeof graphState === "object" ? graphState : null;

    graphRoot.style.minHeight = minHeight + "px";
    // Keep the initial auto-fit height flow-aware, but leave headroom for explicit
    // user resizing instead of clamping the canvas back to the auto height.
    graphRoot.style.maxHeight = viewportMaxHeight + "px";
    if (
      state &&
      Number.isFinite(currentHeight) &&
      Number.isFinite(state.canvasAutoHeight) &&
      Math.abs(currentHeight - state.canvasAutoHeight) > 1
    ) {
      state.canvasUserResized = true;
    }
    if (state && state.canvasUserResized && Number.isFinite(currentHeight)) {
      const clampedHeight = Math.max(minHeight, Math.min(currentHeight, viewportMaxHeight));
      if (Math.abs(clampedHeight - currentHeight) > 1) {
        graphRoot.style.height = clampedHeight + "px";
      }
      state.canvasAutoHeight = clampedHeight;
      return;
    }
    graphRoot.style.height = autoHeight + "px";
    if (state) state.canvasAutoHeight = autoHeight;
  }

  function load(src) {
    return new Promise(function (resolve, reject) {
      const s = document.createElement("script");
      s.src = src;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  function collectPreviewTemplates(rootNode) {
    const utils = window.bpPreviewUtils;
    if (!utils || typeof utils.collectPreviewTemplates !== "function") {
      return new Map();
    }
    return utils.collectPreviewTemplates(
      rootNode || document,
      "template.bp_graph_preview_tpl[data-bp-preview-label]"
    );
  }

  function collectGraphVariants(graphContainer) {
    const payloadNode = graphContainer.select("script.bp-graph-variants").node();
    if (payloadNode) {
      try {
        const parsed = JSON.parse((payloadNode.textContent || "").trim());
        if (Array.isArray(parsed) && parsed.length > 0) {
          return parsed;
        }
      } catch (_err) {}
    }
    const dotTxt = graphContainer.select("script.dot-source").text().trim();
    if (!dotTxt) return [];
    const fallbackDirection = normalizeGraphDirection(graphContainer.attr("data-bp-graph-direction"));
    return [{
      key: "full",
      label: "Full Graph",
      dot: dotTxt,
      direction: fallbackDirection,
      selectOnNodeId: [],
      hoverOnNodeId: []
    }];
  }

  function graphNodeLabel(node) {
    if (!(node instanceof Element)) return "";
    const titleNode = node.querySelector("title");
    const titleTxt =
      titleNode && typeof titleNode.textContent === "string" ? titleNode.textContent.trim() : "";
    if (titleTxt) return titleTxt;
    const textNode = node.querySelector("text");
    const textTxt =
      textNode && typeof textNode.textContent === "string" ? textNode.textContent.trim() : "";
    return textTxt || "";
  }

  function graphNodeId(node) {
    if (!(node instanceof Element)) return "";
    const id = node.getAttribute("id");
    return typeof id === "string" ? id.trim() : "";
  }

  function ensureGraphBlockState(graphBlock) {
    if (!(graphBlock instanceof Element)) return {};
    const existing = graphBlock.__bpGraphState;
    if (existing && typeof existing === "object") return existing;
    const state = {
      previewActiveNode: null,
      previewController: null,
      previewRequestToken: 0,
      groupHoverAnchorNode: null,
      groupHoverController: null,
      groupHoverShownKey: "",
      groupHoverShownNodeId: "",
      graphviz: null,
      renderedVariantKey: "",
      canvasAutoHeight: null,
      canvasUserResized: false,
      renderToken: 0,
      renderFinalizedToken: 0,
      windowHandlersBound: false,
      blockResizeBound: false,
      resizeObserver: null,
      lastBlockWidth: 0,
      lastCanvasWidth: 0,
      lastCanvasHeight: 0
    };
    graphBlock.__bpGraphState = state;
    return state;
  }

  function rememberGraphLayoutMeasurements(graphBlock, graphRoot, graphState) {
    if (
      !(graphBlock instanceof Element) ||
      !(graphRoot instanceof Element) ||
      !graphState ||
      typeof graphState !== "object"
    ) {
      return;
    }
    graphState.lastBlockWidth = Math.round(graphBlock.getBoundingClientRect().width);
    graphState.lastCanvasWidth = Math.round(graphRoot.clientWidth);
    graphState.lastCanvasHeight = Math.round(graphRoot.clientHeight);
  }

  function resizeRenderedGraphToCanvas(graphRoot, graphState) {
    if (!(graphRoot instanceof Element)) return false;
    const svg = graphRoot.querySelector("svg");
    if (!(svg instanceof SVGElement)) return false;
    const nextWidth = Math.round(graphRoot.clientWidth);
    const nextHeight = Math.round(graphRoot.clientHeight);
    if (!(nextWidth > 0) || !(nextHeight > 0)) return false;
    svg.setAttribute("width", String(nextWidth));
    svg.setAttribute("height", String(nextHeight));
    if (graphState && typeof graphState === "object") {
      graphState.lastCanvasWidth = nextWidth;
      graphState.lastCanvasHeight = nextHeight;
    }
    return true;
  }

  function resetGraphvizForVariant(graphRoot, graphState) {
    if (graphRoot instanceof Element) {
      graphRoot.querySelectorAll("svg").forEach(function (svg) {
        svg.remove();
      });
    }
    if (graphState && typeof graphState === "object") {
      graphState.graphviz = null;
      graphState.renderFinalizedToken = 0;
      graphState.lastCanvasWidth = 0;
      graphState.lastCanvasHeight = 0;
      graphState.renderedVariantKey = "";
    }
  }

  function parsePreviewEntry(entry) {
    const utils = window.bpPreviewUtils;
    if (utils && typeof utils.readPreviewTemplate === "function") {
      return utils.readPreviewTemplate(entry);
    }
    if (typeof entry === "string") {
      return entry;
    }
    return "";
  }

  function renderMath(root) {
    const utils = window.bpPreviewUtils;
    if (!utils || typeof utils.renderMath !== "function") return;
    utils.renderMath(root);
  }

  function readPanelNodes(panel, titleSelector, bodySelector) {
    if (!(panel instanceof Element)) {
      return { title: null, body: null };
    }
    const title = panel.querySelector(titleSelector);
    const body = panel.querySelector(bodySelector);
    return {
      title: title instanceof Element ? title : null,
      body: body instanceof Element ? body : null
    };
  }

  function createPanelController(panel, behavior, titleSelector, bodySelector, options) {
    if (!(panel instanceof Element)) return null;
    const nodes = readPanelNodes(panel, titleSelector, bodySelector);
    const opts = options && typeof options === "object" ? options : {};
    const clearBody =
      typeof opts.clearBody === "function"
        ? opts.clearBody
        : function (body) { body.innerHTML = ""; };
    const renderBody =
      typeof opts.renderBody === "function" ? opts.renderBody : function () {};
    const positionPanel =
      typeof opts.positionPanel === "function" ? opts.positionPanel : function () {};
    const onHide =
      typeof opts.onHide === "function" ? opts.onHide : function () {};
    const controller = {
      panel: panel,
      title: nodes.title,
      body: nodes.body,
      behavior: behavior || {
        isPinned: true,
        isHover: false,
        isAnchored: false,
        isDocked: true
      },
      hide: function () {
        panel.hidden = true;
        if (controller.title) controller.title.textContent = "";
        if (controller.body) clearBody(controller.body);
        onHide();
      },
      position: function (anchorNode) {
        positionPanel(panel, anchorNode);
      },
      show: function (titleText, payload, anchorNode) {
        if (!controller.title || !controller.body) return false;
        controller.title.textContent = titleText || "";
        renderBody(controller.body, payload);
        panel.hidden = false;
        controller.position(anchorNode);
        return true;
      }
    };
    return controller;
  }

  function makeHtmlPanelPositioner(behavior) {
    return function (panel, anchorNode) {
      const previewUtils = window.bpPreviewUtils;
      if (
        behavior &&
        behavior.isAnchored &&
        previewUtils &&
        typeof previewUtils.positionAnchoredPanel === "function" &&
        anchorNode instanceof Element
      ) {
        previewUtils.positionAnchoredPanel(panel, anchorNode, 12, 10);
      } else if (previewUtils && typeof previewUtils.resetPanelPosition === "function") {
        previewUtils.resetPanelPosition(panel);
      }
    };
  }

  function makeGroupPanelPositioner(graphBlock, behavior) {
    return function (panel, anchorNode) {
      if (!(panel instanceof Element) || !(graphBlock instanceof Element)) return;
      const previewUtils = window.bpPreviewUtils;
      if (!behavior || !behavior.isAnchored) {
        if (previewUtils && typeof previewUtils.resetPanelPosition === "function") {
          previewUtils.resetPanelPosition(panel);
        }
        return;
      }
      if (!(anchorNode instanceof Element)) return;
      const blockRect = graphBlock.getBoundingClientRect();
      const nodeRect = anchorNode.getBoundingClientRect();
      const panelRect = panel.getBoundingClientRect();
      const gap = 10;

      let left = nodeRect.right - blockRect.left + gap;
      if (left + panelRect.width > blockRect.width - gap) {
        left = nodeRect.left - blockRect.left - panelRect.width - gap;
      }
      let top = nodeRect.top - blockRect.top + (nodeRect.height - panelRect.height) / 2;

      left = Math.max(gap, Math.min(left, blockRect.width - panelRect.width - gap));
      top = Math.max(gap, Math.min(top, blockRect.height - panelRect.height - gap));
      panel.style.left = left + "px";
      panel.style.top = top + "px";
    };
  }

  function configurePanelCloseButton(previewUtils, closeButton, hidePanel, behavior) {
    if (!(closeButton instanceof Element)) return;
    if (previewUtils && typeof previewUtils.configureCloseButton === "function") {
      previewUtils.configureCloseButton(closeButton, hidePanel, behavior);
      return;
    }
    if (behavior && behavior.isPinned) {
      if (previewUtils && typeof previewUtils.bindCloseOnce === "function") {
        previewUtils.bindCloseOnce(closeButton, hidePanel);
      } else if (closeButton.getAttribute("data-bp-bound") !== "1") {
        closeButton.setAttribute("data-bp-bound", "1");
        closeButton.addEventListener("click", function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          hidePanel();
        });
      }
    } else {
      closeButton.hidden = true;
      closeButton.style.display = "none";
      closeButton.setAttribute("aria-hidden", "true");
      closeButton.tabIndex = -1;
    }
  }

  function bindHoverablePanelLifetime(previewUtils, controller, getActiveAnchor, boundAttr) {
    const noop = {
      cancelHide: function () {},
      scheduleHide: function () {
        if (controller) controller.hide();
      }
    };
    if (!controller || !(controller.panel instanceof Element)) return noop;
    if (!controller.behavior || !controller.behavior.isHover) return noop;
    const panel = controller.panel;
    const attr =
      typeof boundAttr === "string" && boundAttr.length > 0
        ? boundAttr
        : "data-bp-preview-hover-bound";
    let hideTimer = null;

    function cancelHide() {
      if (hideTimer !== null) {
        clearTimeout(hideTimer);
        hideTimer = null;
      }
    }

    function scheduleHide() {
      cancelHide();
      hideTimer = window.setTimeout(function () {
        hideTimer = null;
        controller.hide();
      }, 180);
    }

    function maybeScheduleHide(ev) {
      if (
        previewUtils &&
        typeof previewUtils.shouldKeepOpen === "function" &&
        previewUtils.shouldKeepOpen(
          ev.relatedTarget,
          typeof getActiveAnchor === "function" ? getActiveAnchor() : null,
          panel
        )
      ) {
        return;
      }
      scheduleHide();
    }

    if (panel.getAttribute(attr) !== "1") {
      panel.setAttribute(attr, "1");
      panel.addEventListener("mouseenter", cancelHide);
      panel.addEventListener("focusin", cancelHide);
      panel.addEventListener("mouseleave", maybeScheduleHide);
      panel.addEventListener("focusout", maybeScheduleHide);
    }

    return {
      cancelHide: cancelHide,
      scheduleHide: scheduleHide
    };
  }

  function attachPreviewHandlers(graphBlock, graphContainer, previewMap, previewController, previewKeyByNodeId) {
    if (!previewController) return;
    const graphState = ensureGraphBlockState(graphBlock);
    const previewUtils = window.bpPreviewUtils;
    const canResolveSharedPreview =
      previewUtils && typeof previewUtils.loadSharedPreviewEntry === "function";
    const previewKeys =
      previewKeyByNodeId instanceof Map ? previewKeyByNodeId : new Map();
    const hoverLifetime = bindHoverablePanelLifetime(
      previewUtils,
      previewController,
      function () { return graphState.previewActiveNode; },
      "data-bp-preview-hover-bound"
    );
    const svg = graphContainer.select("svg").node();
    if (!svg || !(svg instanceof SVGElement)) {
      previewController.hide();
      return;
    }
    if (!previewController.title || !previewController.body || (previewMap.size === 0 && !canResolveSharedPreview)) {
      previewController.hide();
      return;
    }
    const show = async function (label, anchorNode) {
      const requestToken = ++graphState.previewRequestToken;
      const nodeId = anchorNode instanceof Element ? graphNodeId(anchorNode) : "";
      const previewKey = nodeId ? (previewKeys.get(nodeId) || "") : "";
      let html = parsePreviewEntry(previewMap.get(label));
      if (!html && canResolveSharedPreview && previewKey) {
        const sharedEntry = await previewUtils.loadSharedPreviewEntry(previewKey);
        html = parsePreviewEntry(sharedEntry);
      }
      if (requestToken !== graphState.previewRequestToken) return;
      if (!html) return;
      hoverLifetime.cancelHide();
      graphState.previewActiveNode = anchorNode instanceof Element ? anchorNode : null;
      previewController.show(label, html, graphState.previewActiveNode);
    };
    svg.querySelectorAll("g.node").forEach(function (node) {
      const label = graphNodeLabel(node);
      const nodeId = graphNodeId(node);
      const previewKey = nodeId ? (previewKeys.get(nodeId) || "") : "";
      if (!label || (!previewMap.has(label) && !(canResolveSharedPreview && previewKey))) return;
      node.style.cursor = "pointer";
      node.setAttribute("tabindex", "0");
      const titleNode = node.querySelector("title");
      if (titleNode) titleNode.remove();
      [node].concat(Array.from(node.querySelectorAll("*"))).forEach(function (el) {
        if (!(el instanceof Element)) return;
        if (el.hasAttribute("title")) el.removeAttribute("title");
        if (el.hasAttribute("xlink:title")) el.removeAttribute("xlink:title");
        if (el.removeAttributeNS) {
          el.removeAttributeNS("http://www.w3.org/1999/xlink", "title");
        }
      });
    });
    const showFromTarget = function (target) {
      if (!(target instanceof Element)) return;
      const node = target.closest("g.node");
      if (!node) return;
       if (graphState.previewActiveNode === node && !previewController.panel.hidden) {
        hoverLifetime.cancelHide();
        previewController.position(node);
        return;
      }
      const label = graphNodeLabel(node);
      if (label) show(label, node);
    };
    if (svg.getAttribute("data-bp-preview-bound") === "1") return;
    svg.setAttribute("data-bp-preview-bound", "1");
    svg.addEventListener("mouseover", function (ev) {
      showFromTarget(ev.target);
    });
    svg.addEventListener("focusin", function (ev) {
      showFromTarget(ev.target);
    });
    if (previewController.behavior && previewController.behavior.isHover) {
      const hideIfLeaving = function (ev) {
        if (
          previewUtils &&
          typeof previewUtils.shouldKeepOpen === "function" &&
          previewUtils.shouldKeepOpen(ev.relatedTarget, graphState.previewActiveNode, previewController.panel)
        ) {
          return;
        }
        hoverLifetime.scheduleHide();
      };
      svg.addEventListener("mouseout", hideIfLeaving);
      svg.addEventListener("focusout", hideIfLeaving);
    }
  }

  function attachVariantSelectors(graphContainer, variantsByKey, activeVariant, onSelect, onHover, onHoverLeave) {
    if (!activeVariant) return;
    const mapNodeTargets = function (entries) {
      const out = new Map();
      if (!Array.isArray(entries)) return out;
      entries.forEach(function (entry) {
        if (!Array.isArray(entry) || entry.length !== 2) return;
        const nodeId = String(entry[0] || "").trim();
        const nextKey = String(entry[1] || "").trim();
        if (!nodeId || !nextKey || !variantsByKey.has(nextKey)) return;
        out.set(nodeId, nextKey);
      });
      return out;
    };
    const selectVariantByNodeId = mapNodeTargets(activeVariant.selectOnNodeId);
    const hoverVariantByNodeId = mapNodeTargets(activeVariant.hoverOnNodeId);
    const svg = graphContainer.select("svg").node();
    if (!svg) return;
    const readVariantState = function () {
      const state = svg.__bpVariantState;
      if (state && state.selectVariantByNodeId instanceof Map && state.hoverVariantByNodeId instanceof Map) {
        return state;
      }
      return {
        selectVariantByNodeId: new Map(),
        hoverVariantByNodeId: new Map(),
        lastHoverNodeId: ""
      };
    };
    svg.__bpVariantState = {
      selectVariantByNodeId: selectVariantByNodeId,
      hoverVariantByNodeId: hoverVariantByNodeId,
      lastHoverNodeId: ""
    };

    const nodeSelectKey = function (node) {
      const id = graphNodeId(node);
      if (!id) return "";
      const state = readVariantState();
      return state.selectVariantByNodeId.get(id) || "";
    };
    const activateFromTarget = function (target, ev) {
      if (!(target instanceof Element)) return;
      const node = target.closest("g.node");
      if (!node) return;
      const nextKey = nodeSelectKey(node);
      if (!nextKey) return;
      if (ev) {
        ev.preventDefault();
        ev.stopPropagation();
      }
      onSelect(nextKey);
    };
    const hoverFromTarget = function (target) {
      if (!(target instanceof Element)) return;
      const node = target.closest("g.node");
      if (!node) return;
      const id = graphNodeId(node);
      if (!id) return;
      const state = readVariantState();
      const nextKey = state.hoverVariantByNodeId.get(id) || "";
      if (!nextKey || id === state.lastHoverNodeId) return;
      state.lastHoverNodeId = id;
      onHover(id, nextKey, node);
    };

    svg.querySelectorAll("g.node").forEach(function (node) {
      const selectKey = nodeSelectKey(node);
      const id = graphNodeId(node);
      const state = readVariantState();
      const hoverKey = id ? (state.hoverVariantByNodeId.get(id) || "") : "";
      if (!selectKey && !hoverKey) return;
      node.style.cursor = "pointer";
      node.setAttribute("tabindex", "0");
    });
    if (svg.getAttribute("data-bp-variant-bound") === "1") return;
    svg.setAttribute("data-bp-variant-bound", "1");
    svg.addEventListener("click", function (ev) {
      activateFromTarget(ev.target, ev);
    });
    svg.addEventListener("keydown", function (ev) {
      if (ev.key !== "Enter" && ev.key !== " ") return;
      activateFromTarget(ev.target, ev);
    });
    svg.addEventListener("mouseover", function (ev) {
      hoverFromTarget(ev.target);
    });
    svg.addEventListener("mouseleave", function () {
      const state = readVariantState();
      state.lastHoverNodeId = "";
      if (typeof onHoverLeave === "function") onHoverLeave();
    });
  }

  function syncLegend(graphBlock, activeKey) {
    const fullLegend = graphBlock.querySelector('.bp_graph_legend[data-bp-legend-kind="full"]');
    const groupLegend = graphBlock.querySelector('.bp_graph_legend[data-bp-legend-kind="group"]');
    const showGroupLegend = activeKey === "group";
    if (fullLegend) fullLegend.hidden = showGroupLegend;
    if (groupLegend) groupLegend.hidden = !showGroupLegend;
  }

  function bindLegendPopover(graphBlock) {
    const legendButton = graphBlock.querySelector(".bp_graph_legend_button");
    const legendPanel = graphBlock.querySelector(".bp_graph_legend_popover");
    const legendClose = legendPanel
      ? legendPanel.querySelector(".bp_graph_legend_popover_close")
      : null;
    if (!legendButton || !legendPanel) return null;

    const position = function () {
      const blockRect = graphBlock.getBoundingClientRect();
      const buttonRect = legendButton.getBoundingClientRect();
      const top = Math.max(0, Math.round(buttonRect.bottom - blockRect.top + 8));
      const right = Math.max(0, Math.round(blockRect.right - buttonRect.right));
      legendPanel.style.top = top + "px";
      legendPanel.style.right = right + "px";
    };

    const setOpen = function (isOpen) {
      if (isOpen) position();
      legendPanel.hidden = !isOpen;
      legendButton.setAttribute("aria-expanded", isOpen ? "true" : "false");
    };

    setOpen(false);
    if (legendButton.getAttribute("data-bp-legend-bound") === "1") {
      return {
        open: function () { setOpen(true); },
        close: function () { setOpen(false); },
        position: position
      };
    }
    legendButton.setAttribute("data-bp-legend-bound", "1");

    legendButton.addEventListener("click", function () {
      setOpen(legendPanel.hidden);
    });
    if (legendClose) {
      legendClose.addEventListener("click", function () {
        setOpen(false);
      });
    }
    document.addEventListener("pointerdown", function (ev) {
      if (legendPanel.hidden) return;
      const target = ev.target;
      if (!(target instanceof Node)) return;
      if (graphBlock.contains(target)) return;
      setOpen(false);
    });

    return {
      open: function () { setOpen(true); },
      close: function () { setOpen(false); },
      position: position
    };
  }

  Promise.resolve()
    .then(function () { return load("https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js"); })
    .then(function () { return load("https://cdn.jsdelivr.net/npm/d3-graphviz@5.6.0/build/d3-graphviz.min.js"); })
    .then(function () {
      const graphBlocks = Array.from(document.querySelectorAll(".bp_graph_fullwidth"));
      if (graphBlocks.length === 0) return;

      function initGraphBlock(graphBlock) {
        if (!(graphBlock instanceof Element)) return;
        const graphRoot = graphBlock.querySelector(".bp_graph_canvas");
        if (!graphRoot) return;
        const graphContainer = d3.select(graphRoot);
        if (graphContainer.empty()) return;
        const graphState = ensureGraphBlockState(graphBlock);
        const selector = graphBlock.querySelector(".bp_graph_view_select");
        const previewMap = collectPreviewTemplates(graphBlock);
        const previewPanelNode = graphBlock.querySelector(".bp_graph_preview");
        const previewClose = previewPanelNode
          ? previewPanelNode.querySelector(".bp_graph_preview_close")
          : null;
        const previewUtils = window.bpPreviewUtils;
        const previewPanelBehavior =
          previewUtils && typeof previewUtils.readPanelBehavior === "function"
            ? previewUtils.readPanelBehavior(previewPanelNode, { mode: "pinned", placement: "docked" })
            : { mode: "pinned", placement: "docked", isPinned: true, isHover: false, isAnchored: false, isDocked: true };
        const previewController = createPanelController(
          previewPanelNode,
          previewPanelBehavior,
          ".bp_graph_preview_title",
          ".bp_graph_preview_body",
          {
            clearBody: function (body) { body.innerHTML = ""; },
            renderBody: function (body, html) {
              body.innerHTML = html;
              if (previewUtils && typeof previewUtils.hydratePreviewSubtree === "function") {
                previewUtils.hydratePreviewSubtree(body);
              }
              renderMath(body);
            },
            positionPanel: makeHtmlPanelPositioner(previewPanelBehavior),
            onHide: function () {
              graphState.previewRequestToken += 1;
              graphState.previewActiveNode = null;
            }
          }
        );
        graphState.previewController = previewController;
        configurePanelCloseButton(previewUtils, previewClose, function () {
          if (previewController) previewController.hide();
        }, previewPanelBehavior);

        const rawVariants = collectGraphVariants(graphContainer);
        if (!Array.isArray(rawVariants) || rawVariants.length === 0) return;
        const variantsByKey = new Map();
        rawVariants.forEach(function (variant) {
          if (!variant || typeof variant !== "object") return;
          const key = String(variant.key || "").trim();
          const label = String(variant.label || key).trim();
          const dot = String(variant.dot || "").trim();
          const direction = normalizeGraphDirection(variant.direction);
          const selectOnNodeId = Array.isArray(variant.selectOnNodeId) ? variant.selectOnNodeId : [];
          const hoverOnNodeId = Array.isArray(variant.hoverOnNodeId) ? variant.hoverOnNodeId : [];
          const previewKeyByNodeId = Array.isArray(variant.previewKeyByNodeId) ? variant.previewKeyByNodeId : [];
          if (!key || !dot) return;
          variantsByKey.set(key, {
            key: key,
            label: label || key,
            dot: dot,
            direction: direction,
            selectOnNodeId: selectOnNodeId,
            hoverOnNodeId: hoverOnNodeId,
            previewKeyByNodeId: new Map(previewKeyByNodeId)
          });
        });
        const variants = Array.from(variantsByKey.values());
        if (variants.length === 0) return;

        if (selector && selector.options.length === 0) {
          variants.forEach(function (variant) {
            const option = document.createElement("option");
            option.value = variant.key;
            option.textContent = variant.label;
            selector.appendChild(option);
          });
        }

        let activeKey = variantsByKey.has("full") ? "full" : variants[0].key;
        if (selector && variantsByKey.has(selector.value)) {
          activeKey = selector.value;
        }
        if (selector) selector.value = activeKey;
        syncLegend(graphBlock, activeKey);
        const legendPopover = bindLegendPopover(graphBlock);

        const getActiveVariant = function () {
          const fallback = variantsByKey.get("full") || variants[0];
          return variantsByKey.get(activeKey) || fallback;
        };

        const groupHoverPanel = graphBlock.querySelector(".bp_group_hover_preview");
        const groupHoverClose = groupHoverPanel
          ? groupHoverPanel.querySelector(".bp_group_hover_preview_close")
          : null;
        let groupHoverGraphviz = null;
        const groupHoverBehavior =
          previewUtils && typeof previewUtils.readPanelBehavior === "function"
            ? previewUtils.readPanelBehavior(groupHoverPanel, { mode: "pinned", placement: "docked" })
            : { mode: "pinned", placement: "docked", isPinned: true, isHover: false, isAnchored: false, isDocked: true };
        const groupHoverController = createPanelController(
          groupHoverPanel,
          groupHoverBehavior,
          ".bp_group_hover_preview_title",
          ".bp_group_hover_preview_graph",
          {
            clearBody: function (body) { body.innerHTML = ""; },
            renderBody: function (body, variant) {
              const width = Math.max(320, body.clientWidth || 0);
              const height = Math.max(220, body.clientHeight || 0);
              const container = d3.select(body);
              if (!groupHoverGraphviz) {
                groupHoverGraphviz = container.graphviz().fit(true);
              }
              groupHoverGraphviz
                .width(width)
                .height(height)
                .renderDot(variant.dot);
            },
            positionPanel: makeGroupPanelPositioner(graphBlock, groupHoverBehavior),
            onHide: function () {
              graphState.groupHoverAnchorNode = null;
              graphState.groupHoverShownKey = "";
              graphState.groupHoverShownNodeId = "";
            }
          }
        );
        graphState.groupHoverController = groupHoverController;
        const groupHoverLifetime = bindHoverablePanelLifetime(
          previewUtils,
          groupHoverController,
          function () { return graphState.groupHoverAnchorNode; },
          "data-bp-group-hover-bound"
        );
        configurePanelCloseButton(previewUtils, groupHoverClose, function () {
          if (groupHoverController) groupHoverController.hide();
        }, groupHoverBehavior);

        if (!graphState.windowHandlersBound) {
          graphState.windowHandlersBound = true;
          const repositionPanels = function () {
            if (legendPopover && !graphBlock.querySelector(".bp_graph_legend_popover").hidden) {
              legendPopover.position();
            }
            if (
              graphState.previewController &&
              graphState.previewController.behavior &&
              graphState.previewController.behavior.isAnchored &&
              graphState.previewActiveNode &&
              !graphState.previewController.panel.hidden
            ) {
              graphState.previewController.position(graphState.previewActiveNode);
            }
            if (
              graphState.groupHoverController &&
              graphState.groupHoverController.behavior &&
              graphState.groupHoverController.behavior.isAnchored &&
              graphState.groupHoverAnchorNode &&
              !graphState.groupHoverController.panel.hidden
            ) {
              graphState.groupHoverController.position(graphState.groupHoverAnchorNode);
            }
          };
          window.addEventListener("keydown", function (ev) {
            if (ev.key !== "Escape") return;
            if (legendPopover) legendPopover.close();
            if (graphState.groupHoverController) graphState.groupHoverController.hide();
            if (graphState.previewController) graphState.previewController.hide();
          });
          window.addEventListener("resize", repositionPanels);
          window.addEventListener("scroll", repositionPanels, true);
        }

        const showGroupHoverPreview = function (nodeId, nextKey, anchorNode) {
          if (!groupHoverController) return;
          groupHoverLifetime.cancelHide();
          if (activeKey !== "group") {
            groupHoverController.hide();
            return;
          }
          const variant = variantsByKey.get(nextKey);
          if (!variant || !variant.dot || !nodeId) {
            groupHoverController.hide();
            return;
          }
          if (
            !groupHoverController.panel.hidden &&
            graphState.groupHoverShownKey === nextKey &&
            graphState.groupHoverShownNodeId === nodeId
          ) {
            groupHoverController.position(anchorNode);
            return;
          }
          graphState.groupHoverAnchorNode = anchorNode instanceof Element ? anchorNode : null;
          graphState.groupHoverShownKey = nextKey;
          graphState.groupHoverShownNodeId = nodeId;
          groupHoverController.show("Preview: " + variant.label, variant, graphState.groupHoverAnchorNode);
        };

        const switchVariant = function (nextKey) {
          if (!variantsByKey.has(nextKey) || nextKey === activeKey) return;
          activeKey = nextKey;
          if (selector) selector.value = nextKey;
          syncLegend(graphBlock, activeKey);
          renderGraph();
        };

        const scheduleRender = debounce(function () {
          renderGraph();
        }, 180);

        function renderGraph() {
          const activeVariant = getActiveVariant();
          if (!activeVariant || !activeVariant.dot) return;
          graphState.renderToken += 1;
          const renderToken = graphState.renderToken;
          syncLegend(graphBlock, activeVariant.key);
          if (previewController) previewController.hide();
          if (groupHoverController) groupHoverController.hide();
          layoutGraphCanvas(graphRoot, graphState);
          const width = graphRoot.clientWidth;
          const height = graphRoot.clientHeight;
          rememberGraphLayoutMeasurements(graphBlock, graphRoot, graphState);
          const finalizeRender = function () {
            if (graphState.renderToken !== renderToken) return;
            if (graphState.renderFinalizedToken === renderToken) return;
            graphState.renderFinalizedToken = renderToken;
            attachPreviewHandlers(
              graphBlock,
              graphContainer,
              previewMap,
              previewController,
              activeVariant.previewKeyByNodeId
            );
            attachVariantSelectors(
              graphContainer,
              variantsByKey,
              activeVariant,
              switchVariant,
              showGroupHoverPreview,
              groupHoverBehavior.isHover && groupHoverController
                ? function () { groupHoverLifetime.scheduleHide(); }
                : null
            );
          };

          if (
            graphState.renderedVariantKey &&
            graphState.renderedVariantKey !== activeVariant.key
          ) {
            resetGraphvizForVariant(graphRoot, graphState);
          }
          const gv = graphState.graphviz || graphContainer.graphviz();
          graphState.graphviz = gv;
          graphState.renderedVariantKey = activeVariant.key;
          gv
            .zoom(true)
            .width(width)
            .height(height)
            .fit(true)
            .on("end", function () {
              finalizeRender();
            });
          gv.renderDot(activeVariant.dot);
          setTimeout(function () {
            finalizeRender();
          }, 120);
        }

        if (selector) {
          selector.addEventListener("change", function () {
            switchVariant(selector.value);
          });
        }

        renderGraph();
        if (!graphState.blockResizeBound) {
          graphState.blockResizeBound = true;
          window.addEventListener("resize", scheduleRender);
          if (typeof ResizeObserver === "function") {
            const observer = new ResizeObserver(function (entries) {
              let shouldRender = false;
              entries.forEach(function (entry) {
                if (!entry || !entry.target || !entry.contentRect) return;
                const nextWidth = Math.round(entry.contentRect.width);
                const nextHeight = Math.round(entry.contentRect.height);
                if (entry.target === graphBlock) {
                  if (Math.abs(nextWidth - graphState.lastBlockWidth) > 1) {
                    graphState.lastBlockWidth = nextWidth;
                    shouldRender = true;
                  }
                  return;
                }
                if (entry.target === graphRoot) {
                  const widthChanged = Math.abs(nextWidth - graphState.lastCanvasWidth) > 1;
                  const heightChanged = Math.abs(nextHeight - graphState.lastCanvasHeight) > 1;
                  if (widthChanged) {
                    graphState.lastCanvasWidth = nextWidth;
                    graphState.lastCanvasHeight = nextHeight;
                    shouldRender = true;
                    return;
                  }
                  if (heightChanged) {
                    graphState.lastCanvasWidth = nextWidth;
                    graphState.lastCanvasHeight = nextHeight;
                    if (!resizeRenderedGraphToCanvas(graphRoot, graphState)) {
                      shouldRender = true;
                    }
                  }
                }
              });
              if (shouldRender) scheduleRender();
            });
            observer.observe(graphBlock);
            observer.observe(graphRoot);
            graphState.resizeObserver = observer;
          }
        }
      }

      graphBlocks.forEach(initGraphBlock);
    });
})();
