export const triggerSelector = ".bp_inline_preview_ref[data-bp-preview-id]";

export function getPanel(previewUtils, id, extraClass) {
  const existing = document.getElementById(id);
  if (existing instanceof Element) return existing;
  return previewUtils.createPreviewPanel({
    id: id,
    rootClass: "bp_inline_preview_panel",
    extraClass: extraClass,
    mode: "hover",
    placement: "anchored",
    headerClass: "bp_inline_preview_panel_header",
    headingClass: "bp_inline_preview_panel_heading bp_preview_header_heading",
    titleClass: "bp_inline_preview_panel_title",
    headerLabelClass: "bp_inline_preview_panel_label bp_preview_header_label",
    closeClass: "bp_inline_preview_panel_close",
    closeLabel: "Close inline preview",
    bodyClass: "bp_inline_preview_panel_body",
    footerClass: "bp_inline_preview_panel_footer"
  });
}

export function defaultInlinePreviewHostPolicies(makeBehavior) {
  return [
    {
      selector: ".bp_relation_panel",
      kind: "relation",
      behavior: makeBehavior("hover", "anchored")
    },
    {
      selector: ".bp_graph_preview",
      kind: "graph",
      behavior: makeBehavior("hover", "anchored")
    },
    {
      selector: ".bp_group_hover_preview",
      kind: "graph-group",
      behavior: makeBehavior("hover", "anchored")
    }
  ];
}

export function readInlinePreviewHost(trigger, panel, hostPolicies) {
  if (!(trigger instanceof Element)) return null;
  if (panel.contains(trigger)) return null;
  const policies = Array.isArray(hostPolicies) ? hostPolicies : [];
  for (let i = 0; i < policies.length; i += 1) {
    const policy = policies[i];
    if (!policy || typeof policy.selector !== "string") continue;
    const host = trigger.closest(policy.selector);
    if (!(host instanceof Element)) continue;
    return {
      element: host,
      kind: typeof policy.kind === "string" && policy.kind ? policy.kind : "generic",
      behavior: policy.behavior && typeof policy.behavior === "object"
        ? policy.behavior
        : { mode: "hover", placement: "anchored" }
    };
  }
  return null;
}

export function bindInlinePreview(previewUtils) {
  if (!(document.body instanceof Element)) return;
  if (document.body.getAttribute("data-bp-inline-preview-bound") === "1") return;
  document.body.setAttribute("data-bp-inline-preview-bound", "1");

  const previewDebug = previewUtils.previewDebug;
  const previewDebugLabel = previewUtils.previewDebugLabel;

  function makeBehavior(mode, placement) {
    return { mode: mode, placement: placement };
  }

  const inlineHostPolicies = defaultInlinePreviewHostPolicies(makeBehavior);

  const mainSurface = previewUtils.createPreviewSurface({
    panel: getPanel(previewUtils, "bp-inline-preview-panel", ""),
    titleSelector: ".bp_inline_preview_panel_title",
    headerLabelSelector: ".bp_inline_preview_panel_label",
    bodySelector: ".bp_inline_preview_panel_body",
    footerSelector: ".bp_inline_preview_panel_footer",
    closeSelector: ".bp_inline_preview_panel_close",
    footerHtmlAttr: "data-bp-preview-footer-html",
    defaults: { mode: "hover", placement: "anchored" },
    onClose: hidePanel
  });
  const childSurface = previewUtils.createPreviewSurface({
    panel: getPanel(
      previewUtils,
      "bp-inline-preview-child-panel",
      "bp_inline_preview_panel_child"
    ),
    titleSelector: ".bp_inline_preview_panel_title",
    headerLabelSelector: ".bp_inline_preview_panel_label",
    bodySelector: ".bp_inline_preview_panel_body",
    footerSelector: ".bp_inline_preview_panel_footer",
    closeSelector: ".bp_inline_preview_panel_close",
    footerHtmlAttr: "data-bp-preview-footer-html",
    defaults: { mode: "hover", placement: "anchored" },
    onClose: hideChildPanel
  });
  if (!mainSurface || !childSurface) return;
  const panel = mainSurface.panel;
  const childPanel = childSurface.panel;

  let behavior = mainSurface.setBehavior(makeBehavior("hover", "anchored"));
  let activeTrigger = null;
  let activeHost = null;
  let activePreviewKey = "";
  let updatingPanel = false;
  let ignoreNextPanelExit = false;
  let showRequestToken = 0;
  let childActiveTrigger = null;
  let childShowRequestToken = 0;
  let mainLifecycle = null;
  let childLifecycle = null;
  const childBehavior = childSurface.setBehavior(makeBehavior("hover", "anchored"));

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
    if (mainLifecycle) mainLifecycle.cancelHide();
  }

  function cancelChildHide() {
    if (childLifecycle) childLifecycle.cancelHide();
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
    behavior = mainSurface.setBehavior(nextBehavior || makeBehavior("hover", "anchored"));
    activeHost = hostInfo || null;
    if (activeHost && activeHost.kind) {
      panel.setAttribute("data-bp-inline-host", activeHost.kind);
    } else {
      panel.removeAttribute("data-bp-inline-host");
    }
  }

  function triggerInsideInlinePanel(trigger) {
    return trigger instanceof Element && (panel.contains(trigger) || childPanel.contains(trigger));
  }

  function bindInlinePreviewTriggers(root) {
    if (mainLifecycle) mainLifecycle.refresh(root);
    if (childLifecycle) childLifecycle.refresh(root);
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
    mainSurface.hideContent();
    activeTrigger = null;
    activeHost = null;
    activePreviewKey = "";
    applyBehavior(makeBehavior("hover", "anchored"), null);
  }

  function hideChildPanel() {
    cancelChildHide();
    childShowRequestToken += 1;
    childSurface.hideContent();
    childActiveTrigger = null;
  }

  async function resolveInlinePreviewHtml(key, trigger) {
    const previewLookupKey =
      trigger instanceof Element
        ? (trigger.getAttribute("data-bp-preview-key") || "").trim()
        : "";
    if (!previewLookupKey) return "";
    const resolved = await previewUtils.resolvePreviewHtml(previewLookupKey);
    return resolved.html || "";
  }

  async function showChildFromTrigger(trigger) {
    if (!(trigger instanceof Element)) return;
    const key = (trigger.getAttribute("data-bp-preview-id") || "").trim();
    if (!key) {
      hideChildPanel();
      return;
    }
    const requestToken = ++childShowRequestToken;
    const html = await resolveInlinePreviewHtml(key, trigger);
    if (requestToken !== childShowRequestToken) return;
    if (!html) {
      hideChildPanel();
      return;
    }
    const heading = (trigger.getAttribute("data-bp-preview-title") || key).trim() || key;
    cancelHide();
    cancelChildHide();
    childActiveTrigger = trigger;
    childSurface.showContent({
      heading: heading,
      html: html,
      behavior: childBehavior,
      anchor: trigger,
      source: trigger
    });
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
    const html = await resolveInlinePreviewHtml(key, trigger);
    if (requestToken !== showRequestToken) return;
    if (!html) {
      hidePanel();
      return;
    }
    const heading = (trigger.getAttribute("data-bp-preview-title") || key).trim() || key;
    activePreviewKey = key;
    const inPanel = panel.contains(trigger);
    const hostInfo = inPanel
      ? activeHost
      : readInlinePreviewHost(trigger, panel, inlineHostPolicies);
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
      mainSurface.replaceBody({
        heading: heading,
        html: html,
        source: trigger
      });
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
      mainSurface.showContent({
        heading: heading,
        html: html,
        behavior: behavior,
        anchor: trigger,
        source: trigger
      });
      if (behavior.isDocked && activeHost) {
        positionDockedPanel(activeHost);
      }
    }
  }

  function mainTriggerLeaveHandled(trigger, ev) {
    if (!trigger.isConnected) return true;
    const triggerKey = (trigger.getAttribute("data-bp-preview-id") || "").trim();
    if (triggerKey && activePreviewKey && triggerKey !== activePreviewKey) return true;
    if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return true;
    if (panel.matches(":hover") || panel.matches(":focus-within")) return true;
    previewDebug("inline.trigger.leave", {
      triggerKey: triggerKey,
      activePreviewKey: activePreviewKey,
      trigger: previewDebugLabel(trigger),
      relatedTarget: previewDebugLabel(ev.relatedTarget),
      panelHover: panel.matches(":hover"),
      panelFocus: panel.matches(":focus-within"),
      updatingPanel: updatingPanel
    });
    return false;
  }

  function mainPanelLeaveHandled(_panel, ev) {
    if (updatingPanel) return true;
    if (ignoreNextPanelExit) {
      ignoreNextPanelExit = false;
      previewDebug("inline.panel.leave.ignored", {
        activePreviewKey: activePreviewKey,
        relatedTarget: previewDebugLabel(ev.relatedTarget),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within")
      });
      return true;
    }
    if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return true;
    if (mainSurface.pointerWithin(ev)) return true;
    if (panel.matches(":hover") || panel.matches(":focus-within")) return true;
    previewDebug("inline.panel.leave", {
      activePreviewKey: activePreviewKey,
      activeTrigger: previewDebugLabel(activeTrigger),
      relatedTarget: previewDebugLabel(ev.relatedTarget),
      panelHover: panel.matches(":hover"),
      panelFocus: panel.matches(":focus-within"),
      updatingPanel: updatingPanel
    });
    return false;
  }

  function childTriggerLeaveHandled(_trigger, _ev) {
    return childPanel.matches(":hover") || childPanel.matches(":focus-within");
  }

  function childPanelLeaveHandled(_panel, ev) {
    return childSurface.pointerWithin(ev);
  }

  function repositionPanels() {
    if (behavior.isAnchored && activeTrigger && !panel.hidden) {
      mainSurface.position(activeTrigger, behavior);
    } else if (behavior.isDocked && activeHost && !panel.hidden) {
      positionDockedPanel(activeHost);
    }
    if (childActiveTrigger && !childPanel.hidden) {
      childSurface.position(childActiveTrigger, childBehavior);
    }
  }

  applyBehavior(behavior, null);
  mainLifecycle = mainSurface.bindTriggers({
    triggerRoot: document,
    triggerSelector: triggerSelector,
    triggerBoundAttr: "data-bp-inline-main-bound",
    filterTrigger: function (trigger) { return !triggerInsideInlinePanel(trigger); },
    show: showFromTrigger,
    hide: hidePanel,
    getActiveTrigger: function () { return activeTrigger; },
    onLeave: mainTriggerLeaveHandled,
    onPanelLeave: mainPanelLeaveHandled,
    bindWindow: false
  });
  childLifecycle = childSurface.bindTriggers({
    triggerRoot: document,
    triggerSelector: triggerSelector,
    triggerBoundAttr: "data-bp-inline-child-bound",
    filterTrigger: triggerInsideInlinePanel,
    show: showChildFromTrigger,
    hide: hideChildPanel,
    getActiveTrigger: function () { return childActiveTrigger; },
    onLeave: childTriggerLeaveHandled,
    onPanelLeave: childPanelLeaveHandled,
    bindEscape: false,
    bindWindow: false
  });
  mainSurface.bindRepositioner({
    owner: document.body,
    boundAttr: "data-bp-inline-panel-reposition-bound",
    reposition: repositionPanels
  });

  previewUtils.registerPreviewHydrator("inline", refresh);

  refresh(document);
}

export function startInlinePreview(previewUtils) {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      bindInlinePreview(previewUtils);
    });
  } else {
    bindInlinePreview(previewUtils);
  }
}

export const inlinePreviewRuntime = {
  triggerSelector,
  getPanel,
  defaultInlinePreviewHostPolicies,
  readInlinePreviewHost,
  bindInlinePreview,
  startInlinePreview
};

export default inlinePreviewRuntime;
