import * as graphRuntimeCoreModule from "./graph-runtime-core.mjs";
import { getGraphData as coreGetGraphData, getGraphVariants as coreGetGraphVariants } from "../blueprint-graph-core.mjs";

const {
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
} = graphRuntimeCoreModule;

function readPublicGraphData(root) {
  return coreGetGraphData(root);
}

function readPublicGraphVariants(root) {
  const variants = coreGetGraphVariants(root);
  if (Array.isArray(variants) && variants.length > 0) {
    return variants;
  }
  return [];
}

function dotWithGraphAttribute(dot, name, value) {
  const source = String(dot || "");
  if (!source) return "";
  const attrPattern = new RegExp("(^\\s*" + name + "\\s*=\\s*)([^;]+)(\\s*;)", "mi");
  if (attrPattern.test(source)) {
    return source.replace(attrPattern, "$1" + value + "$3");
  }
  const openBrace = source.indexOf("{");
  if (openBrace < 0) return source;
  return source.slice(0, openBrace + 1) + "\n    " + name + "=" + value + ";" + source.slice(openBrace + 1);
}

function dotWithGraphOptions(dot, options) {
  const source = String(dot || "").trim();
  if (!source) return "";
  const normalized = normalizeGraphOptions(options);
  let updated = dotWithGraphAttribute(source, "rankdir", normalized.direction);
  updated = dotWithGraphAttribute(updated, "pack", graphPackAttr(normalized.pack));
  return updated;
}

function dotForVariantOptions(variant, options) {
  if (!variant || typeof variant !== "object") return "";
  return dotWithGraphOptions(variant.dot, options);
}

// Runtime graph-data rendering consumes Lean-computed variants from public GraphData,
// then feeds the generated block into the same initializer used by page graphs.
let runtimeGraphIdCounter = 0;

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function stringValue(value, fallback) {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return typeof fallback === "string" ? fallback : "";
}

function graphName(value) {
  return stringValue(value, "").trim();
}

function htmlIdKey(value) {
  let out = "";
  for (const char of String(value || "")) {
    if (/^[A-Za-z0-9]$/.test(char)) {
      out += char;
    } else if (char === "-") {
      out += "--";
    } else {
      out += "-" + char.codePointAt(0).toString(16).toUpperCase().padStart(4, "0");
    }
  }
  return out;
}

function prefixedHtmlId(prefix, value) {
  const body = htmlIdKey(value);
  return body ? prefix + "-" + body : prefix;
}

function normalizePublicGraphData(rawData) {
  if (!rawData || typeof rawData !== "object" || Array.isArray(rawData)) return null;
  const data = rawData;
  return {
    schemaVersion: Number.isFinite(Number(data.schemaVersion)) ? Number(data.schemaVersion) : 1,
    key: stringValue(data.key, "graph"),
    nodes: asArray(data.nodes),
    edges: asArray(data.edges),
    groups: asArray(data.groups),
    variants: asArray(data.variants)
  };
}

function graphOptionsFromRenderOptions(options, variants) {
  const opts = options && typeof options === "object" ? options : {};
  const rawOptions =
    opts.graphOptions && typeof opts.graphOptions === "object"
      ? opts.graphOptions
      : opts.options && typeof opts.options === "object"
        ? opts.options
        : variants[0] && variants[0].options && typeof variants[0].options === "object"
          ? variants[0].options
          : opts;
  return normalizeGraphOptions(rawOptions);
}

function graphVariantsFromRenderOptions(data, options) {
  const opts = options && typeof options === "object" ? options : {};
  const rawVariants = asArray(opts.variants).length > 0 ? asArray(opts.variants) : asArray(data && data.variants);
  return rawVariants.filter(function (variant) {
    return variant && typeof variant === "object" && graphName(variant.key) && stringValue(variant.dot, "").trim();
  });
}

function createEl(doc, tagName, attrs, text) {
  const el = doc.createElement(tagName);
  Object.entries(attrs || {}).forEach(function (entry) {
    const name = entry[0];
    const value = entry[1];
    if (value === null || typeof value === "undefined" || value === false) return;
    if (value === true) {
      el.setAttribute(name, name);
    } else {
      el.setAttribute(name, String(value));
    }
  });
  if (typeof text === "string") el.textContent = text;
  return el;
}

function appendSelectOption(doc, select, value, label, selected) {
  const option = createEl(doc, "option", { value: value }, label);
  if (selected) option.selected = true;
  select.appendChild(option);
  return option;
}

function appendJsonScript(doc, parent, className, value) {
  const script = createEl(doc, "script", {
    type: "application/json",
    class: className
  });
  script.textContent = JSON.stringify(value || null);
  parent.appendChild(script);
  return script;
}

function createPreviewPanel(doc, classes, headerClass, titleClass, closeClass, bodyClass, closeLabel, mode, placement) {
  const panel = createEl(doc, "aside", {
    class: classes,
    "data-bp-preview-mode": mode,
    "data-bp-preview-placement": placement,
    hidden: true
  });
  const header = createEl(doc, "div", { class: headerClass });
  header.appendChild(createEl(doc, "div", { class: titleClass }));
  header.appendChild(createEl(doc, "button", {
    type: "button",
    class: closeClass,
    "aria-label": closeLabel
  }, "Close"));
  panel.appendChild(header);
  panel.appendChild(createEl(doc, "div", { class: bodyClass }));
  return panel;
}

function graphControlId(data, suffix) {
  runtimeGraphIdCounter += 1;
  return prefixedHtmlId("bp-runtime-graph", (data && data.key ? data.key : "graph") + "-" + runtimeGraphIdCounter) + suffix;
}

export function createGraphBlock(graphData, options) {
  const opts = options && typeof options === "object" ? options : {};
  const data = normalizePublicGraphData(graphData);
  if (!data) return null;
  const doc = opts.document && typeof opts.document.createElement === "function" ? opts.document : document;
  const variants = graphVariantsFromRenderOptions(data, opts);
  if (variants.length === 0) return null;
  const graphOptions = graphOptionsFromRenderOptions(opts, variants);
  const block = createEl(doc, "div", { class: "bp_graph_fullwidth", "data-bp-graph-source": "runtime" });
  if (opts.layout) block.setAttribute("data-bp-graph-layout", graphLayoutMode(block, opts));
  const graphViewSelectId = graphControlId(data, "--view");
  const graphDirectionSelectId = graphControlId(data, "--direction");
  const graphPackInputId = graphControlId(data, "--pack");
  const graphPreviewModeSelectId = graphControlId(data, "--preview-mode");
  const graphPreviewPlacementSelectId = graphControlId(data, "--preview-placement");
  const graphLegendPanelId = graphControlId(data, "--legend");
  const graphOptionsPanelId = graphControlId(data, "--options");
  const previewMode = String(opts.previewMode || "pinned");
  const previewPlacement = String(opts.previewPlacement || "docked");

  const controls = createEl(doc, "div", { class: "bp_graph_controls" });
  const primary = createEl(doc, "div", { class: "bp_graph_controls_primary" });
  primary.appendChild(createEl(doc, "button", {
    type: "button",
    class: "bp_graph_controls_button bp_graph_legend_button",
    "aria-haspopup": "dialog",
    "aria-expanded": "false",
    "aria-controls": graphLegendPanelId
  }, "Legend"));
  primary.appendChild(createEl(doc, "label", { class: "bp_graph_controls_label", for: graphViewSelectId }, "View"));
  const viewSelect = createEl(doc, "select", { id: graphViewSelectId, class: "bp_graph_controls_select bp_graph_view_select" });
  variants.forEach(function (variant, index) {
    appendSelectOption(doc, viewSelect, variant.key, variant.label || variant.key, index === 0);
  });
  primary.appendChild(viewSelect);
  controls.appendChild(primary);
  const actions = createEl(doc, "div", { class: "bp_graph_controls_actions" });
  actions.appendChild(createEl(doc, "button", {
    type: "button",
    class: "bp_graph_controls_button bp_graph_options_button",
    "aria-haspopup": "dialog",
    "aria-expanded": "false",
    "aria-controls": graphOptionsPanelId
  }, "Graph options"));
  controls.appendChild(actions);
  block.appendChild(controls);

  const legendPopover = createEl(doc, "div", { id: graphLegendPanelId, class: "bp_graph_legend_popover", hidden: true });
  const legendHeader = createEl(doc, "div", { class: "bp_graph_legend_popover_header" });
  legendHeader.appendChild(createEl(doc, "span", { class: "bp_graph_legend_popover_title" }, "Legend"));
  legendHeader.appendChild(createEl(doc, "button", { type: "button", class: "bp_graph_legend_popover_close", "aria-label": "Close legend" }, "Close"));
  legendPopover.appendChild(legendHeader);
  const legendBody = createEl(doc, "div", { class: "bp_graph_legend_popover_body" });
  legendBody.appendChild(createEl(doc, "div", { class: "bp_graph_legend", "data-bp-legend-kind": "full" }));
  if (variants.some(function (variant) { return variant.key === "group"; })) {
    legendBody.appendChild(createEl(doc, "div", { class: "bp_graph_legend", "data-bp-legend-kind": "group", hidden: true }));
  }
  legendPopover.appendChild(legendBody);
  block.appendChild(legendPopover);

  const optionsPopover = createEl(doc, "div", { id: graphOptionsPanelId, class: "bp_graph_options_popover", hidden: true });
  const optionsHeader = createEl(doc, "div", { class: "bp_graph_options_popover_header" });
  optionsHeader.appendChild(createEl(doc, "span", { class: "bp_graph_options_popover_title" }, "Graph options"));
  optionsHeader.appendChild(createEl(doc, "button", { type: "button", class: "bp_graph_options_popover_close", "aria-label": "Close graph options" }, "Close"));
  optionsPopover.appendChild(optionsHeader);
  const optionsBody = createEl(doc, "div", { class: "bp_graph_options_popover_body" });
  optionsBody.appendChild(createEl(doc, "label", { class: "bp_graph_controls_label", for: graphDirectionSelectId }, "Direction"));
  const directionSelect = createEl(doc, "select", {
    id: graphDirectionSelectId,
    class: "bp_graph_controls_select bp_graph_direction_select",
    "data-bp-graph-default-direction": graphOptions.direction
  });
  ["TB", "LR", "RL", "BT"].forEach(function (direction) {
    appendSelectOption(doc, directionSelect, direction, direction, direction === graphOptions.direction);
  });
  optionsBody.appendChild(directionSelect);
  const packLabel = createEl(doc, "label", { class: "bp_graph_option_toggle", for: graphPackInputId });
  const packInput = createEl(doc, "input", {
    id: graphPackInputId,
    type: "checkbox",
    class: "bp_graph_pack_input",
    "data-bp-graph-default-pack": graphPackAttr(graphOptions.pack),
    checked: graphOptions.pack
  });
  packInput.checked = !!graphOptions.pack;
  packLabel.appendChild(packInput);
  packLabel.appendChild(createEl(doc, "span", {}, "Pack disconnected components"));
  optionsBody.appendChild(packLabel);
  optionsBody.appendChild(createEl(doc, "label", { class: "bp_graph_controls_label", for: graphPreviewModeSelectId }, "Preview"));
  const previewModeSelect = createEl(doc, "select", {
    id: graphPreviewModeSelectId,
    class: "bp_graph_controls_select bp_graph_preview_mode_select",
    "data-bp-graph-default-preview-mode": previewMode
  });
  appendSelectOption(doc, previewModeSelect, "pinned", "Click to pin", previewMode !== "hover");
  appendSelectOption(doc, previewModeSelect, "hover", "Hover", previewMode === "hover");
  optionsBody.appendChild(previewModeSelect);
  optionsBody.appendChild(createEl(doc, "label", { class: "bp_graph_controls_label", for: graphPreviewPlacementSelectId }, "Position"));
  const previewPlacementSelect = createEl(doc, "select", {
    id: graphPreviewPlacementSelectId,
    class: "bp_graph_controls_select bp_graph_preview_placement_select",
    "data-bp-graph-default-preview-placement": previewPlacement
  });
  appendSelectOption(doc, previewPlacementSelect, "docked", "Docked", previewPlacement !== "anchored");
  appendSelectOption(doc, previewPlacementSelect, "anchored", "Near node", previewPlacement === "anchored");
  optionsBody.appendChild(previewPlacementSelect);
  optionsPopover.appendChild(optionsBody);
  block.appendChild(optionsPopover);

  const canvas = createEl(doc, "div", {
    class: "bp_graph_canvas",
    "data-bp-graph-direction": graphOptions.direction,
    "data-bp-graph-pack": graphPackAttr(graphOptions.pack)
  });
  appendJsonScript(doc, canvas, "bp-graph-data", data);
  appendJsonScript(doc, canvas, "bp-graph-variants", variants);
  block.appendChild(canvas);
  block.appendChild(createPreviewPanel(
    doc,
    "bp_graph_preview bp_preview_panel",
    "bp_graph_preview_header bp_preview_panel_header",
    "bp_graph_preview_title bp_preview_panel_title",
    "bp_graph_preview_close bp_preview_panel_close",
    "bp_graph_preview_body bp_preview_panel_body",
    "Close informal preview",
    previewMode,
    previewPlacement
  ));
  block.appendChild(createPreviewPanel(
    doc,
    "bp_group_hover_preview bp_preview_panel",
    "bp_group_hover_preview_header bp_preview_panel_header",
    "bp_group_hover_preview_title bp_preview_panel_title",
    "bp_group_hover_preview_close bp_preview_panel_close",
    "bp_group_hover_preview_graph bp_preview_panel_body",
    "Close group preview",
    previewMode,
    previewPlacement
  ));
  return block;
}

function readGraphNodeSvgHref(node) {
  if (!(node instanceof Element)) return "";
  const links = [];
  if (String(node.localName || "").toLowerCase() === "a") links.push(node);
  node.querySelectorAll("a").forEach(function (link) {
    links.push(link);
  });
  for (const link of links) {
    const href = (
      link.getAttribute("href") ||
      link.getAttribute("xlink:href") ||
      (link.getAttributeNS
        ? link.getAttributeNS("http://www.w3.org/1999/xlink", "href")
        : "") ||
      ""
    ).trim();
    if (href.length > 0) return href;
  }
  return "";
}

function graphDataNodeForPreview(graphData, label, previewKey) {
  if (!graphData || typeof graphData !== "object" || !Array.isArray(graphData.nodes)) return null;
  const normalizedLabel = String(label || "").trim();
  const normalizedPreviewKey = String(previewKey || "").trim();
  return graphData.nodes.find(function (node) {
    if (!node || typeof node !== "object") return false;
    const nodePreviewKey = typeof node.previewKey === "string" ? node.previewKey.trim() : "";
    const nodeLabel = typeof node.label === "string" ? node.label.trim() : "";
    const nodeDisplayLabel = typeof node.displayLabel === "string" ? node.displayLabel.trim() : "";
    return (
      (normalizedPreviewKey.length > 0 && nodePreviewKey === normalizedPreviewKey) ||
      (normalizedLabel.length > 0 && (nodeLabel === normalizedLabel || nodeDisplayLabel === normalizedLabel))
    );
  }) || null;
}

function graphPreviewHref(graphData, node, label, previewKey) {
  const svgHref = readGraphNodeSvgHref(node);
  if (svgHref.length > 0) return svgHref;
  const graphNode = graphDataNodeForPreview(graphData, label, previewKey);
  return graphNode && typeof graphNode.href === "string" ? graphNode.href.trim() : "";
}

function graphPreviewLinkTitle(graphData, label, previewKey) {
  const graphNode = graphDataNodeForPreview(graphData, label, previewKey);
  const graphTitle = graphNode && typeof graphNode.title === "string" ? graphNode.title.trim() : "";
  const normalizedLabel = String(label || "").trim();
  return graphTitle && normalizedLabel && graphTitle !== normalizedLabel ? normalizedLabel : "";
}

function graphPreviewHeading(graphData, label, previewKey) {
  const graphNode = graphDataNodeForPreview(graphData, label, previewKey);
  const graphTitle = graphNode && typeof graphNode.title === "string" ? graphNode.title.trim() : "";
  return graphTitle || String(label || "").trim();
}

function attachPreviewHandlers(previewUtils, graphBlock, graphContainer, previewController, previewKeyByNodeId) {
  if (!previewController) return;
  const graphState = ensureGraphBlockState(graphBlock);
  const previewKeys =
    previewKeyByNodeId instanceof Map ? previewKeyByNodeId : new Map();
  const svg = graphContainer.select("svg").node();
  if (!svg || !(svg instanceof SVGElement)) {
    previewController.hide();
    return;
  }
  if (!previewController.title || !previewController.body || previewKeys.size === 0) {
    previewController.hide();
    return;
  }
  const show = async function (label, anchorNode) {
    const requestToken = ++graphState.previewRequestToken;
    const nodeId = anchorNode instanceof Element ? graphNodeId(anchorNode) : "";
    const previewKey = nodeId ? (previewKeys.get(nodeId) || "") : "";
    if (!previewKey) return;
    const resolved = await previewUtils.resolvePreviewHtml(previewKey);
    if (resolved && resolved.reason === "semantic-preview-body-missing") return;
    const html = resolved.html || "";
    if (requestToken !== graphState.previewRequestToken) return;
    if (!html) return;
    graphState.previewActiveNode = anchorNode instanceof Element ? anchorNode : null;
    previewController.showContent({
      heading: graphPreviewHeading(graphState.graphData, label, previewKey),
      headingHref: graphPreviewHref(graphState.graphData, graphState.previewActiveNode, label, previewKey),
      headingTitle: graphPreviewLinkTitle(graphState.graphData, label, previewKey),
      html: html,
      anchor: graphState.previewActiveNode
    });
  };
  const canPreviewNode = function (node) {
    if (!(node instanceof Element)) return false;
    const nodeId = graphNodeId(node);
    const previewKey = nodeId ? (previewKeys.get(nodeId) || "") : "";
    return !!previewKey;
  };
  svg.querySelectorAll("g.node").forEach(function (node) {
    if (!canPreviewNode(node)) return;
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
  const showFromNode = function (node) {
    if (!(node instanceof Element) || !canPreviewNode(node)) return false;
    if (graphState.previewActiveNode === node && !previewController.panel.hidden) {
      previewController.position(node);
      return true;
    }
    const label = graphNodeLabel(node);
    show(label, node);
    return true;
  };
  previewController.bindTriggers({
    eventRoot: svg,
    eventRootBoundAttr: "data-bp-preview-bound",
    triggerSelector: "g.node",
    filterTrigger: canPreviewNode,
    show: showFromNode,
    hide: function () { previewController.hide(); },
    getActiveTrigger: function () { return graphState.previewActiveNode; },
    activateOnClick: true,
    activateOnKeydown: true,
    enterRequiresHover: true,
    bindEscape: false,
    bindWindow: false
  });
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

function bindGraphPopover(previewUtils, graphBlock, buttonSelector, panelSelector, closeSelector, boundAttr) {
  const triggerButton = graphBlock.querySelector(buttonSelector);
  const popoverPanel = graphBlock.querySelector(panelSelector);
  const popoverClose = popoverPanel
    ? popoverPanel.querySelector(closeSelector)
    : null;
  return previewUtils.bindAnchoredPopover({
    root: graphBlock,
    trigger: triggerButton,
    panel: popoverPanel,
    close: popoverClose,
    boundAttr: boundAttr,
    offset: 8,
    position: function (_controller, rootNode, triggerNode, panelNode) {
      if (!(rootNode instanceof Element)) return;
      if (!(triggerNode instanceof Element)) return;
      if (!(panelNode instanceof HTMLElement)) return;
      const rootRect = rootNode.getBoundingClientRect();
      const triggerRect = triggerNode.getBoundingClientRect();
      const top = Math.max(0, Math.round(triggerRect.bottom - rootRect.top + 8));
      panelNode.style.top = top + "px";
      if (rootRect.width <= 720) {
        panelNode.style.left = "0px";
        panelNode.style.right = "0px";
        return;
      }
      const right = Math.max(0, Math.round(rootRect.right - triggerRect.right));
      panelNode.style.left = "";
      panelNode.style.right = right + "px";
    }
  });
}

function bindLegendPopover(previewUtils, graphBlock) {
  return bindGraphPopover(
    previewUtils,
    graphBlock,
    ".bp_graph_legend_button",
    ".bp_graph_legend_popover",
    ".bp_graph_legend_popover_close",
    "data-bp-legend-bound"
  );
}

function bindOptionsPopover(previewUtils, graphBlock) {
  return bindGraphPopover(
    previewUtils,
    graphBlock,
    ".bp_graph_options_button",
    ".bp_graph_options_popover",
    ".bp_graph_options_popover_close",
    "data-bp-options-bound"
  );
}

export function initGraphBlock(previewUtils, graphBlock, options) {
      const opts = options && typeof options === "object" ? options : {};
      if (!(graphBlock instanceof Element)) return;
      const graphRoot = graphBlock.querySelector(".bp_graph_canvas");
      if (!graphRoot) return;
      if (opts.layout) {
        const layoutMode = graphLayoutMode(graphRoot, opts);
        graphBlock.setAttribute("data-bp-graph-layout", layoutMode);
        graphRoot.setAttribute("data-bp-graph-layout", layoutMode);
      }
      const graphContainer = d3.select(graphRoot);
      if (graphContainer.empty()) return;
      const graphState = ensureGraphBlockState(graphBlock);
      const existingController =
        graphState.controller && graphState.controller.__bpGraphController
          ? graphState.controller
          : (
            graphBlock.__bpGraphController &&
              graphBlock.__bpGraphController.__bpGraphController
              ? graphBlock.__bpGraphController
              : null
          );
      if (existingController) return existingController;
      const graphApiData = readPublicGraphData(graphBlock);
      if (graphApiData) {
        graphState.graphData = graphApiData;
        graphBlock.__bpGraphData = graphApiData;
      }
      const selector = graphBlock.querySelector(".bp_graph_view_select");
      const directionSelector = graphBlock.querySelector(".bp_graph_direction_select");
      const packInput = graphBlock.querySelector(".bp_graph_pack_input");
      const previewModeSelector = graphBlock.querySelector(".bp_graph_preview_mode_select");
      const previewPlacementSelector = graphBlock.querySelector(".bp_graph_preview_placement_select");
      const previewPanelNode = graphBlock.querySelector(".bp_graph_preview");
      const previewPanelBehavior = readPreviewBehaviorDefaults(previewPanelNode, "pinned", "docked");
      let previewController = null;
      previewController = previewUtils.createPreviewSurface({
        panel: previewPanelNode,
        titleSelector: ".bp_graph_preview_title",
        bodySelector: ".bp_graph_preview_body",
        closeSelector: ".bp_graph_preview_close",
        defaults: {
          mode: previewPanelBehavior.mode,
          placement: previewPanelBehavior.placement
        },
        onHide: function () {
          graphState.previewRequestToken += 1;
          graphState.previewActiveNode = null;
        }
      });
      graphState.previewController = previewController;
      const readPreviewMode = function () {
        if (previewModeSelector) return previewModeSelector.value;
        if (previewController && previewController.behavior) return previewController.behavior.mode;
        return previewPanelBehavior.mode || "pinned";
      };
      const readPreviewPlacement = function () {
        if (previewPlacementSelector) return previewPlacementSelector.value;
        if (previewController && previewController.behavior) return previewController.behavior.placement;
        return previewPanelBehavior.placement || "docked";
      };
      const setPreviewBehavior = function (nextMode, nextPlacement, options) {
        const opts = options && typeof options === "object" ? options : {};
        const behavior = previewController
          ? previewController.setBehavior({ mode: nextMode, placement: nextPlacement })
          : {
            mode: nextMode || previewPanelBehavior.mode || "pinned",
            placement: nextPlacement || previewPanelBehavior.placement || "docked"
          };
        const mode = behavior.mode;
        const placement = behavior.placement;
        if (previewPanelNode && !previewController) {
          previewPanelNode.setAttribute("data-bp-preview-mode", mode);
          previewPanelNode.setAttribute("data-bp-preview-placement", placement);
        }
        if (previewModeSelector) previewModeSelector.value = mode;
        if (previewPlacementSelector) previewPlacementSelector.value = placement;
        if (previewController) {
          if (!opts.keepOpen) previewController.hide();
        }
        return behavior;
      };
      setPreviewBehavior(
        previewModeSelector
          ? (previewModeSelector.getAttribute("data-bp-graph-default-preview-mode") || previewModeSelector.value)
          : (previewPanelBehavior.mode || "pinned"),
        previewPlacementSelector
          ? (previewPlacementSelector.getAttribute("data-bp-graph-default-preview-placement") || previewPlacementSelector.value)
          : (previewPanelBehavior.placement || "docked"),
        { keepOpen: true }
      );

      const rawVariants = readPublicGraphVariants(graphBlock);
      if (!Array.isArray(rawVariants) || rawVariants.length === 0) return;
      const variantsByKey = new Map();
      rawVariants.forEach(function (variant) {
        if (!variant || typeof variant !== "object") return;
        const key = String(variant.key || "").trim();
        const label = String(variant.label || key).trim();
        const dot = String(variant.dot || "").trim();
        const options = normalizeGraphOptions(
          variant.options && typeof variant.options === "object"
            ? variant.options
            : { direction: variant.direction, pack: variant.pack }
        );
        const selectOnNodeId = Array.isArray(variant.selectOnNodeId) ? variant.selectOnNodeId : [];
        const hoverOnNodeId = Array.isArray(variant.hoverOnNodeId) ? variant.hoverOnNodeId : [];
        const previewKeyByNodeId = Array.isArray(variant.previewKeyByNodeId) ? variant.previewKeyByNodeId : [];
        if (!key || !dot) return;
        variantsByKey.set(key, {
          key: key,
          label: label || key,
          dot: dot,
          options: options,
          selectOnNodeId: selectOnNodeId,
          hoverOnNodeId: hoverOnNodeId,
          previewKeyByNodeId: new Map(previewKeyByNodeId)
        });
      });
      const variants = Array.from(variantsByKey.values());
      if (variants.length === 0) return;
      graphBlock.__bpGraphVariants = variants;

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
      let activeOptions = normalizeGraphOptions({
        direction: directionSelector
          ? directionSelector.getAttribute("data-bp-graph-default-direction")
          : graphContainer.attr("data-bp-graph-direction"),
        pack: packInput
          ? packInput.getAttribute("data-bp-graph-default-pack")
          : graphContainer.attr("data-bp-graph-pack")
      });
      if (directionSelector) directionSelector.value = activeOptions.direction;
      if (packInput) packInput.checked = activeOptions.pack;
      syncLegend(graphBlock, activeKey);
      const legendPopover = bindLegendPopover(previewUtils, graphBlock);
      const optionsPopover = bindOptionsPopover(previewUtils, graphBlock);

      const getActiveVariant = function () {
        const fallback = variantsByKey.get("full") || variants[0];
        return variantsByKey.get(activeKey) || fallback;
      };

      const getActiveOptions = function () {
        return normalizeGraphOptions(activeOptions);
      };

      const groupHoverPanel = graphBlock.querySelector(".bp_group_hover_preview");
      let groupHoverGraphviz = null;
      const groupHoverBehavior = readPreviewBehaviorDefaults(groupHoverPanel, "pinned", "docked");
      let groupHoverController = null;
      groupHoverController = previewUtils.createPreviewSurface({
        panel: groupHoverPanel,
        titleSelector: ".bp_group_hover_preview_title",
        bodySelector: ".bp_group_hover_preview_graph",
        closeSelector: ".bp_group_hover_preview_close",
        defaults: {
          mode: groupHoverBehavior.mode,
          placement: groupHoverBehavior.placement
        },
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
            .renderDot(dotForVariantOptions(variant, getActiveOptions()));
        },
        positionPanel: makeGroupPanelPositioner(graphBlock, function () {
          return groupHoverController ? groupHoverController.behavior : groupHoverBehavior;
        }),
        onHide: function () {
          graphState.groupHoverAnchorNode = null;
          graphState.groupHoverShownKey = "";
          graphState.groupHoverShownNodeId = "";
        }
      });
      graphState.groupHoverController = groupHoverController;
      const groupHoverLifetime = groupHoverController
        ? groupHoverController.bindTriggers({
          panelBoundAttr: "data-bp-group-hover-bound",
          hide: function () {
            if (groupHoverController) groupHoverController.hide();
          },
          getActiveTrigger: function () { return graphState.groupHoverAnchorNode; },
          bindEscape: false,
          bindWindow: false
        })
        : {
          cancelHide: function () {},
          scheduleHide: function () {}
        };

      const lifecycleSurface = previewController || groupHoverController;
      if (!graphState.windowHandlersBound && lifecycleSurface) {
        graphState.windowHandlersBound = true;
        const repositionPanels = function () {
          if (legendPopover && legendPopover.isOpen()) {
            legendPopover.position();
          }
          if (optionsPopover && optionsPopover.isOpen()) {
            optionsPopover.position();
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
        lifecycleSurface.bindDismissal({
          owner: graphBlock,
          boundAttr: "data-bp-graph-panel-dismiss-bound",
          closeButton: null,
          bindTrigger: false,
          bindOutside: false,
          bindEscape: true,
          isOpen: function () {
            return (
              (legendPopover && legendPopover.isOpen()) ||
              (optionsPopover && optionsPopover.isOpen()) ||
              (
                graphState.groupHoverController &&
                graphState.groupHoverController.panel &&
                !graphState.groupHoverController.panel.hidden
              ) ||
              (
                graphState.previewController &&
                graphState.previewController.panel &&
                !graphState.previewController.panel.hidden
              )
            );
          },
          close: function () {
            if (legendPopover) legendPopover.close();
            if (optionsPopover) optionsPopover.close();
            if (graphState.groupHoverController) graphState.groupHoverController.hide();
            if (graphState.previewController) graphState.previewController.hide();
          }
        });
        lifecycleSurface.bindRepositioner({
          owner: graphBlock,
          boundAttr: "data-bp-graph-panel-reposition-bound",
          reposition: repositionPanels
        });
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

      const switchGraphOptions = function (nextOptions) {
        const rawNextOptions = nextOptions && typeof nextOptions === "object" ? nextOptions : {};
        const normalized = normalizeGraphOptions({
          direction: Object.prototype.hasOwnProperty.call(rawNextOptions, "direction")
            ? rawNextOptions.direction
            : activeOptions.direction,
          pack: Object.prototype.hasOwnProperty.call(rawNextOptions, "pack")
            ? rawNextOptions.pack
            : activeOptions.pack
        });
        if (graphOptionsKey(normalized) === graphOptionsKey(activeOptions)) return;
        activeOptions = normalized;
        if (directionSelector) directionSelector.value = normalized.direction;
        if (packInput) packInput.checked = normalized.pack;
        renderGraph();
      };

      const switchDirection = function (nextDirection) {
        switchGraphOptions({ direction: nextDirection });
      };

      const switchPack = function (nextPack) {
        switchGraphOptions({ pack: nextPack });
      };

      const scheduleRender = debounce(function () {
        renderGraph();
      }, 180);

      function renderGraph() {
        const activeVariant = getActiveVariant();
        const options = getActiveOptions();
        const optionsKey = graphOptionsKey(options);
        const dot = dotForVariantOptions(activeVariant, options);
        if (!activeVariant || !dot) return;
        graphState.renderToken += 1;
        const renderToken = graphState.renderToken;
        syncLegend(graphBlock, activeVariant.key);
        if (previewController) previewController.hide();
        if (groupHoverController) groupHoverController.hide();
        layoutGraphCanvas(graphRoot, graphState, opts);
        const width = graphRoot.clientWidth;
        const height = graphRoot.clientHeight;
        rememberGraphLayoutMeasurements(graphBlock, graphRoot, graphState);
        const finalizeRender = function () {
          if (graphState.renderToken !== renderToken) return;
          if (graphState.renderFinalizedToken === renderToken) return;
          graphState.renderFinalizedToken = renderToken;
          attachPreviewHandlers(
            previewUtils,
            graphBlock,
            graphContainer,
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
          (graphState.renderedVariantKey &&
            graphState.renderedVariantKey !== activeVariant.key) ||
          (graphState.renderedOptionsKey &&
            graphState.renderedOptionsKey !== optionsKey)
        ) {
          resetGraphvizForVariant(graphRoot, graphState);
        }
        const gv = graphState.graphviz || graphContainer.graphviz();
        graphState.graphviz = gv;
        graphState.renderedVariantKey = activeVariant.key;
        graphState.renderedOptionsKey = optionsKey;
        graphRoot.setAttribute("data-bp-active-direction", options.direction);
        graphRoot.setAttribute("data-bp-active-pack", graphPackAttr(options.pack));
        gv
          .zoom(true)
          .width(width)
          .height(height)
          .fit(true)
          .on("end", function () {
            finalizeRender();
          });
        gv.renderDot(dot);
        setTimeout(function () {
          finalizeRender();
        }, 120);
      }

      if (selector) {
        selector.addEventListener("change", function () {
          switchVariant(selector.value);
        });
      }
      if (directionSelector) {
        directionSelector.addEventListener("change", function () {
          switchDirection(directionSelector.value);
          if (optionsPopover) optionsPopover.close();
        });
      }
      if (packInput) {
        packInput.addEventListener("change", function () {
          switchPack(packInput.checked);
        });
      }
      if (previewModeSelector) {
        previewModeSelector.addEventListener("change", function () {
          setPreviewBehavior(previewModeSelector.value, readPreviewPlacement());
        });
      }
      if (previewPlacementSelector) {
        previewPlacementSelector.addEventListener("change", function () {
          setPreviewBehavior(readPreviewMode(), previewPlacementSelector.value);
        });
      }

      const controller = {
        __bpGraphController: true,
        block: graphBlock,
        canvas: graphRoot,
        state: graphState,
        variants: variants,
        variantsByKey: variantsByKey,
        getActiveVariant: getActiveVariant,
        getActiveOptions: getActiveOptions,
        layout: function (layoutOptions) {
          layoutGraphCanvas(graphRoot, graphState, layoutOptions || opts);
          return controller;
        },
        render: function () {
          renderGraph();
          return controller;
        },
        scheduleRender: function () {
          scheduleRender();
          return controller;
        },
        setView: function (nextKey) {
          switchVariant(nextKey);
          return controller;
        },
        setVariant: function (nextKey) {
          switchVariant(nextKey);
          return controller;
        },
        setOptions: function (nextOptions) {
          switchGraphOptions(nextOptions);
          return controller;
        },
        setDirection: function (nextDirection) {
          switchDirection(nextDirection);
          return controller;
        },
        setPack: function (nextPack) {
          switchPack(nextPack);
          return controller;
        },
        setPreviewBehavior: function (nextMode, nextPlacement, behaviorOptions) {
          setPreviewBehavior(nextMode, nextPlacement, behaviorOptions);
          return controller;
        }
      };
      graphState.controller = controller;
      graphBlock.__bpGraphController = controller;

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
      return controller;
    }

const defaultGraphRuntimeLibraryUrls = {
  d3: "https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js",
  graphviz: "https://cdn.jsdelivr.net/npm/d3-graphviz@5.6.0/build/d3-graphviz.min.js"
};

let graphRuntimeLibrariesPromise = null;

function readGraphRuntimeLibraryUrls(options) {
  const opts = options && typeof options === "object" ? options : {};
  const libs = opts.libraries && typeof opts.libraries === "object" ? opts.libraries : {};
  return {
    d3: typeof libs.d3 === "string" && libs.d3.length > 0 ? libs.d3 : defaultGraphRuntimeLibraryUrls.d3,
    graphviz:
      typeof libs.graphviz === "string" && libs.graphviz.length > 0
        ? libs.graphviz
        : defaultGraphRuntimeLibraryUrls.graphviz
  };
}

function hasD3Library() {
  return !!(window.d3 && typeof window.d3.select === "function");
}

function hasGraphvizLibrary() {
  if (!hasD3Library()) return false;
  try {
    const probe = document.createElement("div");
    return typeof window.d3.select(probe).graphviz === "function";
  } catch (_err) {
    return false;
  }
}

export function ensureGraphRuntimeLibraries(options) {
  const urls = readGraphRuntimeLibraryUrls(options);
  if (hasGraphvizLibrary()) return Promise.resolve();
  if (!graphRuntimeLibrariesPromise) {
    graphRuntimeLibrariesPromise = Promise.resolve()
      .then(function () {
        if (hasD3Library()) return null;
        return load(urls.d3);
      })
      .then(function () {
        if (hasGraphvizLibrary()) return null;
        return load(urls.graphviz);
      })
      .catch(function (err) {
        graphRuntimeLibrariesPromise = null;
        throw err;
      });
  }
  return graphRuntimeLibrariesPromise;
}

export function getGraphRenderApi(options) {
  const opts = options && typeof options === "object" ? options : {};
  if (opts.previewUtils && typeof opts.previewUtils === "object") {
    return Promise.resolve(opts.previewUtils);
  }
  return Promise.reject(
    new Error("Blueprint graph rendering requires options.previewUtils from createPreview().")
  );
}

function isGraphSearchRoot(root) {
  return (
    root instanceof Element ||
    root instanceof Document ||
    (typeof DocumentFragment !== "undefined" && root instanceof DocumentFragment)
  );
}

function graphBlocksIn(root) {
  const scope = isGraphSearchRoot(root) ? root : document;
  const blocks = [];
  if (scope instanceof Element && scope.matches(".bp_graph_fullwidth")) {
    blocks.push(scope);
  }
  if (typeof scope.querySelectorAll === "function") {
    scope.querySelectorAll(".bp_graph_fullwidth").forEach(function (block) {
      if (block instanceof Element && blocks.indexOf(block) < 0) {
        blocks.push(block);
      }
    });
  }
  return blocks;
}

function normalizeGraphRenderArgs(root, options) {
  if (isGraphSearchRoot(root)) {
    return {
      root: root,
      options: options && typeof options === "object" ? options : {}
    };
  }
  return {
    root: document,
    options: root && typeof root === "object" ? root : {}
  };
}

export async function renderGraphBlock(graphBlock, options) {
  const opts = options && typeof options === "object" ? options : {};
  const previewUtils = await getGraphRenderApi(opts);
  await ensureGraphRuntimeLibraries(opts);
  const controller = initGraphBlock(previewUtils, graphBlock, opts);
  if (opts.refresh && controller && typeof controller.render === "function") {
    controller.render();
  }
  return controller || null;
}

export async function renderGraphs(root, options) {
  const args = normalizeGraphRenderArgs(root, options);
  const blocks = graphBlocksIn(args.root);
  if (blocks.length === 0) return [];
  const previewUtils = await getGraphRenderApi(args.options);
  await ensureGraphRuntimeLibraries(args.options);
  return blocks
    .map(function (block) {
      const controller = initGraphBlock(previewUtils, block, args.options);
      if (args.options.refresh && controller && typeof controller.render === "function") {
        controller.render();
      }
      return controller || null;
    })
    .filter(function (controller) { return !!controller; });
}

export async function renderGraphData(host, graphData, options) {
  const opts = options && typeof options === "object" ? options : {};
  if (!(host instanceof Element)) return null;
  const block = createGraphBlock(graphData, Object.assign({}, opts, { document: host.ownerDocument || document }));
  if (!block) return null;
  if (opts.replace === false) {
    host.appendChild(block);
  } else {
    host.replaceChildren(block);
  }
  return renderGraphBlock(block, opts);
}

export function installGraphRenderApi(previewUtils, options) {
  if (!previewUtils || typeof previewUtils !== "object") return {};
  const installed = {
    ensureGraphRuntimeLibraries: ensureGraphRuntimeLibraries,
    createGraphBlock: function (graphData, nextOptions) {
      return createGraphBlock(
        graphData,
        Object.assign({}, options || {}, nextOptions || {})
      );
    },
    initGraphBlock: function (graphBlock, nextOptions) {
      return initGraphBlock(
        previewUtils,
        graphBlock,
        Object.assign({}, options || {}, nextOptions || {})
      );
    },
    renderGraphBlock: function (graphBlock, nextOptions) {
      return renderGraphBlock(
        graphBlock,
        Object.assign({}, options || {}, nextOptions || {}, { previewUtils: previewUtils })
      );
    },
    renderGraphs: function (root, nextOptions) {
      if (!isGraphSearchRoot(root) && root && typeof root === "object" && !nextOptions) {
        return renderGraphs(
          Object.assign({}, options || {}, root, { previewUtils: previewUtils })
        );
      }
      return renderGraphs(
        root,
        Object.assign({}, options || {}, nextOptions || {}, { previewUtils: previewUtils })
      );
    },
    renderGraphData: function (host, graphData, nextOptions) {
      return renderGraphData(
        host,
        graphData,
        Object.assign({}, options || {}, nextOptions || {}, { previewUtils: previewUtils })
      );
    }
  };
  Object.assign(previewUtils, installed);
  return installed;
}

export function bindGraphs(previewUtils, options) {
    const opts = options && typeof options === "object" ? options : {};
    const root = isGraphSearchRoot(opts.root) ? opts.root : document;
    const graphBlocks = graphBlocksIn(root);
    if (graphBlocks.length === 0) return Promise.resolve([]);
    return ensureGraphRuntimeLibraries(opts)
      .then(function () {
        return graphBlocks
          .map(function (graphBlock) {
            return initGraphBlock(previewUtils, graphBlock, opts) || null;
          })
          .filter(function (controller) { return !!controller; });
      });
}

export function startGraphRuntime(previewUtils, options) {
  installGraphRenderApi(previewUtils, options);
  if (document.readyState === "loading") {
    return new Promise(function (resolve, reject) {
      document.addEventListener("DOMContentLoaded", function () {
        bindGraphs(previewUtils, options).then(resolve, reject);
      }, { once: true });
    });
  } else {
    return bindGraphs(previewUtils, options);
  }
}

export const graphRuntime = {
  ensureGraphRuntimeLibraries,
  getGraphRenderApi,
  createGraphBlock,
  initGraphBlock,
  renderGraphBlock,
  renderGraphs,
  renderGraphData,
  installGraphRenderApi,
  bindGraphs,
  startGraphRuntime
};

export default graphRuntime;
