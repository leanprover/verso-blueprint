  // Graph command runtime helpers.

  export function debounce(fn, waitMs) {
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

  function normalizeGraphPack(rawPack) {
    if (rawPack === false) return false;
    if (rawPack === true) return true;
    const pack = rawPack === null || typeof rawPack === "undefined" ? "" : String(rawPack).trim().toLowerCase();
    if (pack === "") return false;
    if (pack === "false" || pack === "0" || pack === "no" || pack === "off") {
      return false;
    }
    return true;
  }

  function normalizeGraphLayout(rawLayout) {
    const layout = String(rawLayout || "").trim().toLowerCase();
    if (layout === "fill" || layout === "embed" || layout === "slide") return "fill";
    if (layout === "block" || layout === "single") return "block";
    return "page";
  }

  export function normalizeGraphOptions(rawOptions) {
    const options = rawOptions && typeof rawOptions === "object" ? rawOptions : {};
    return {
      direction: normalizeGraphDirection(options.direction),
      pack: normalizeGraphPack(Object.prototype.hasOwnProperty.call(options, "pack") ? options.pack : false)
    };
  }

  export function graphPackAttr(pack) {
    return normalizeGraphPack(pack) ? "true" : "false";
  }

  export function graphOptionsKey(options) {
    const normalized = normalizeGraphOptions(options);
    return normalized.direction + "|" + graphPackAttr(normalized.pack);
  }

  export function graphLayoutMode(graphRoot, options) {
    const opts = options && typeof options === "object" ? options : {};
    if (Object.prototype.hasOwnProperty.call(opts, "layout")) {
      return normalizeGraphLayout(opts.layout);
    }
    if (graphRoot instanceof Element) {
      const attrLayout = graphRoot.getAttribute("data-bp-graph-layout");
      if (attrLayout) return normalizeGraphLayout(attrLayout);
      const block = graphRoot.closest(".bp_graph_fullwidth");
      if (block instanceof Element) {
        const blockLayout = block.getAttribute("data-bp-graph-layout");
        if (blockLayout) return normalizeGraphLayout(blockLayout);
      }
    }
    try {
      const path = window.location && typeof window.location.pathname === "string"
        ? window.location.pathname
        : "";
      if (path.indexOf("/html-single/") >= 0 || /\/html-single\/?$/.test(path)) {
        return "block";
      }
    } catch (_err) {}
    return "page";
  }

  export function readPreviewBehaviorDefaults(panel, fallbackMode, fallbackPlacement) {
    if (!(panel instanceof Element)) {
      return {
        mode: fallbackMode,
        placement: fallbackPlacement
      };
    }
    return {
      mode: panel.getAttribute("data-bp-preview-mode") || fallbackMode,
      placement: panel.getAttribute("data-bp-preview-placement") || fallbackPlacement
    };
  }

  function readGraphCanvasFlowBottom(graphRoot, layoutMode) {
    if (!(graphRoot instanceof Element)) return 0;
    const block = graphRoot.closest(".bp_graph_fullwidth");
    if (layoutMode === "block" || layoutMode === "fill") {
      if (block instanceof Element) return block.getBoundingClientRect().bottom;
      return graphRoot.getBoundingClientRect().bottom;
    }
    const flowContainer = graphRoot.closest(".content-wrapper") || graphRoot.closest("main");
    if (!(flowContainer instanceof Element)) return 0;
    const rect = flowContainer.getBoundingClientRect();
    return rect.bottom;
  }

  function updateGraphCanvasOffset(graphRoot) {
    if (!(graphRoot instanceof Element)) return;
    const block = graphRoot.closest(".bp_graph_fullwidth");
    if (!(block instanceof HTMLElement)) return;
    block.style.setProperty(
      "--bp-graph-canvas-top",
      Math.max(0, Math.round(graphRoot.offsetTop)) + "px"
    );
  }

  function layoutGraphCanvasFill(graphRoot, graphState) {
    const rect = graphRoot.getBoundingClientRect();
    const parent = graphRoot.parentElement;
    const parentRect = parent instanceof Element ? parent.getBoundingClientRect() : null;
    const viewportHeight = readViewportHeight();
    const fallbackHeight = Math.max(280, Math.floor(viewportHeight * 0.7));
    let nextHeight = fallbackHeight;
    if (parentRect && parentRect.height > 0) {
      nextHeight = Math.floor(parentRect.bottom - rect.top);
    } else if (graphRoot.clientHeight > 0) {
      nextHeight = graphRoot.clientHeight;
    }
    nextHeight = Math.max(1, nextHeight);
    graphRoot.style.minHeight = "0px";
    graphRoot.style.maxHeight = "none";
    graphRoot.style.height = nextHeight + "px";
    graphRoot.style.resize = "none";
    if (graphState && typeof graphState === "object") {
      graphState.canvasAutoHeight = nextHeight;
    }
  }

  export function layoutGraphCanvas(graphRoot, graphState, options) {
    if (!(graphRoot instanceof Element)) return;
    updateGraphCanvasOffset(graphRoot);
    const layoutMode = graphLayoutMode(graphRoot, options);
    if (layoutMode === "fill") {
      layoutGraphCanvasFill(graphRoot, graphState);
      return;
    }
    const rect = graphRoot.getBoundingClientRect();
    const viewportHeight = readViewportHeight();
    const bottomGap = 20;
    const viewportMaxHeight = Math.max(280, Math.floor(viewportHeight * 0.84));
    const flowBottom = readGraphCanvasFlowBottom(graphRoot, layoutMode);
    const trailingHeight = Math.max(0, flowBottom - rect.bottom);
    const rawAvailableHeight = Math.floor(viewportHeight - rect.top - bottomGap - trailingHeight);
    const availableHeight =
      layoutMode === "block" && rawAvailableHeight < 280
        ? viewportMaxHeight
        : Math.max(1, rawAvailableHeight);
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

  export function load(src) {
    return new Promise(function (resolve, reject) {
      const s = document.createElement("script");
      s.src = src;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  export function graphNodeLabel(node) {
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

  export function graphNodeId(node) {
    if (!(node instanceof Element)) return "";
    const id = node.getAttribute("id");
    return typeof id === "string" ? id.trim() : "";
  }

  export function ensureGraphBlockState(graphBlock) {
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
      graphData: null,
      graphviz: null,
      renderedVariantKey: "",
      renderedOptionsKey: "",
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

  export function rememberGraphLayoutMeasurements(graphBlock, graphRoot, graphState) {
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

  export function resizeRenderedGraphToCanvas(graphRoot, graphState) {
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

  export function resetGraphvizForVariant(graphRoot, graphState) {
    let cachedGraphviz = null;
    if (graphState && typeof graphState === "object" && graphState.graphviz) {
      cachedGraphviz = graphState.graphviz;
    } else if (graphRoot instanceof Element && graphRoot.__graphviz__) {
      cachedGraphviz = graphRoot.__graphviz__;
    }
    // d3-graphviz caches zoom state on the canvas. Destroy the renderer first
    // so the replacement SVG gets fresh D3 zoom handlers.
    if (cachedGraphviz && typeof cachedGraphviz.destroy === "function") {
      cachedGraphviz.destroy();
    } else if (graphRoot instanceof Element && graphRoot.__graphviz__) {
      delete graphRoot.__graphviz__;
    }
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
      graphState.renderedOptionsKey = "";
    }
  }

  function readBehaviorSource(behaviorSource) {
    if (typeof behaviorSource === "function") {
      const behavior = behaviorSource();
      return behavior && typeof behavior === "object" ? behavior : null;
    }
    return behaviorSource && typeof behaviorSource === "object" ? behaviorSource : null;
  }

  function resetPanelPosition(panel) {
    if (!(panel instanceof Element)) return;
    panel.style.left = "";
    panel.style.top = "";
  }

  export function makeGroupPanelPositioner(graphBlock, behaviorSource) {
    return function (panel, anchorNode) {
      const behavior = readBehaviorSource(behaviorSource);
      if (!(panel instanceof Element) || !(graphBlock instanceof Element)) return;
      if (!behavior || !behavior.isAnchored) {
        resetPanelPosition(panel);
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

  export const graphRuntimeCore = {
    debounce,
    normalizeGraphOptions,
    graphPackAttr,
    graphOptionsKey,
    graphLayoutMode,
    readPreviewBehaviorDefaults,
    layoutGraphCanvas,
    load,
    graphNodeLabel,
    graphNodeId,
    ensureGraphBlockState,
    rememberGraphLayoutMeasurements,
    resizeRenderedGraphToCanvas,
    resetGraphvizForVariant,
    makeGroupPanelPositioner
  };

export default graphRuntimeCore;
