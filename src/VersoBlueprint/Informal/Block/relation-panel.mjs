// Relation popups: the blocks a block uses, the blocks that use it, and its group.
//
// Lean renders a chip and the rows as data (`RelatedPanel.renderPanel`). The popup
// is built from the shared preview panel shell the first time it opens: the header
// names the popup and its block, and the body lists the rows beside a preview of the
// selected one. `data-bp-preview-mode` chooses how it opens: `pinned` on click,
// `hover` on hover. A click pins it either way.

const hideDelay = 180;

export function relationPreviewDiagnosticOptions(detail) {
  return {
    kind: "error",
    title: "Preview unavailable",
    detail: detail || "The preview cache content could not be loaded."
  };
}

const relationBadges = {
  s: { className: "bp_relation_badge_axis bp_relation_badge_statement", title: "Declared in the statement", text: "statement" },
  p: { className: "bp_relation_badge_axis bp_relation_badge_proof", title: "Declared in the proof", text: "proof" },
  oa: { className: "bp_relation_badge_origin bp_relation_badge_origin_automatic", title: "Origin: automatic", text: "automatic" },
  ia: { className: "bp_relation_badge_intent bp_relation_badge_intent_auxiliary", title: "Intent: auxiliary", text: "auxiliary" },
  it: { className: "bp_relation_badge_intent bp_relation_badge_intent_technical", title: "Intent: technical", text: "technical" }
};

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (typeof text === "string") node.textContent = text;
  return node;
}

function readEntries(wrap) {
  const script = wrap.querySelector(":scope > script.bp-relation-entries");
  if (!(script instanceof Element)) return [];
  const raw = (script.textContent || "").trim();
  script.remove();
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_err) {
    return [];
  }
}

function statusMark(status) {
  const mark = element("span", "bp_relation_status");
  mark.setAttribute("aria-hidden", "true");
  if (Array.isArray(status) && typeof status[0] === "string" && typeof status[1] === "string") {
    mark.classList.add("bp_code_link_status_" + status[1]);
    mark.appendChild(element("span", "bp_code_status_symbol", status[0]));
  }
  return mark;
}

// Must match RelatedPanel.panelEntryDataHtml; positional because large blueprints
// can have thousands of relation rows:
// [title, previewKey?, label, href?, badgeCodes, active, status?, current].
function createRow(entry) {
  if (!Array.isArray(entry)) return null;
  const row = {
    title: typeof entry[0] === "string" ? entry[0] : "",
    previewKey: typeof entry[1] === "string" ? entry[1] : "",
    label: typeof entry[2] === "string" ? entry[2] : "",
    href: typeof entry[3] === "string" ? entry[3] : "",
    active: entry[5] === true,
    current: entry[7] === true,
    element: null
  };
  const item = element("li", "bp_relation_item");
  if (row.current) item.classList.add("bp_relation_item_current");
  if (row.previewKey) item.setAttribute("data-bp-relation-preview-key", row.previewKey);
  if (row.label) item.setAttribute("data-bp-preview-header-label", row.label);
  if (row.href) item.setAttribute("data-bp-preview-header-href", row.href);

  // One line per row: status mark, title, and badges. The label is in the row's
  // tooltip and in the preview heading of the selected row.
  const target = element(row.href && !row.current ? "a" : "span", "bp_relation_target");
  if (target instanceof HTMLAnchorElement) target.href = row.href;
  if (row.label) target.title = row.label;
  target.appendChild(statusMark(entry[6]));
  target.appendChild(element("span", "bp_relation_target_name", row.title || row.label));
  if (row.current) target.appendChild(element("span", "bp_relation_current_tag", "this block"));
  (Array.isArray(entry[4]) ? entry[4] : []).forEach(function (code) {
    const spec = relationBadges[code];
    if (!spec) return;
    const badge = element("span", "bp_relation_axis_badge " + spec.className, spec.text);
    badge.title = spec.title;
    target.appendChild(badge);
  });
  item.appendChild(target);
  row.element = item;
  return row;
}

export function bindRelationPanel(previewUtils, wrap) {
  if (!(wrap instanceof Element)) return;
  if (wrap.getAttribute("data-bp-bound") === "1") return;
  const chip = wrap.querySelector(":scope > button.bp_relation_chip");
  if (!(chip instanceof HTMLElement)) return;
  wrap.setAttribute("data-bp-bound", "1");

  const mode = wrap.getAttribute("data-bp-preview-mode") === "hover" ? "hover" : "pinned";
  // Slides lay their popups out inside the slide; elsewhere the popup is placed in
  // the viewport beside its chip.
  const inSlide = !!wrap.closest(".bp_slide_node");
  // Rows are parsed when the popup first opens: large blueprints have thousands.
  let rows = [];
  const loadingHtml = previewUtils.previewMessageHtml({ kind: "loading", title: "Loading preview" });
  let view = null;
  let pinned = false;
  let hideTimer = null;
  let requestToken = 0;

  function isOpen() {
    return !!view && !view.panel.hidden;
  }

  function withinPopup(node) {
    if (!(node instanceof Node)) return false;
    if (chip.contains(node)) return true;
    if (view && view.panel.contains(node)) return true;
    // A reference previewed from inside this popup opens its own inline popup.
    return node instanceof Element && !!node.closest(".bp_inline_preview_panel");
  }

  function cancelHide() {
    if (hideTimer !== null) window.clearTimeout(hideTimer);
    hideTimer = null;
  }

  function scheduleHide(ev) {
    if (pinned || withinPopup(ev && ev.relatedTarget)) return;
    cancelHide();
    hideTimer = window.setTimeout(close, hideDelay);
  }

  function buildView() {
    rows = readEntries(wrap).map(createRow).filter(Boolean);
    const listed = rows.filter(function (row) { return !row.current; });
    const eyebrow = wrap.getAttribute("data-bp-relation-eyebrow") || "";
    const ownerTitle = wrap.getAttribute("data-bp-relation-title") || "";
    const ownerLabel = wrap.getAttribute("data-bp-relation-label") || "";
    const ownerHref = wrap.getAttribute("data-bp-relation-href") || "";
    const note = wrap.getAttribute("data-bp-relation-note") || "";
    const panel = previewUtils.createPreviewPanel({
      roleClass: "bp_relation_panel" +
        (inSlide ? "" : " bp_relation_panel_placed") +
        (listed.length === 1 ? " bp_relation_panel_single" : ""),
      eyebrow: eyebrow,
      mode: mode,
      placement: "anchored",
      closeLabel: "Close " + (eyebrow || "popup").toLowerCase(),
      parent: inSlide ? wrap : document.body
    });
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-label", [eyebrow, ownerTitle].filter(Boolean).join(": "));
    const title = panel.querySelector(".bp_preview_panel_title");
    if (title) title.textContent = ownerTitle;
    const label = panel.querySelector(".bp_preview_panel_label");
    if (label instanceof HTMLAnchorElement && ownerLabel) {
      label.textContent = ownerLabel;
      if (ownerHref) label.href = ownerHref;
      label.hidden = false;
    }

    const body = panel.querySelector(".bp_preview_panel_body");
    if (note) body.appendChild(element("div", "bp_relation_note", note));
    const list = element("ul", "bp_relation_list");
    rows.forEach(function (row) {
      list.appendChild(row.element);
      if (row.current) return;
      row.element.addEventListener("mouseenter", function () { activate(row); });
      row.element.addEventListener("focusin", function () { activate(row); });
    });
    const preview = element("section", "bp_relation_preview");
    const heading = element("div", "bp_relation_preview_heading");
    heading.appendChild(element("span", "bp_relation_preview_title"));
    const previewLabel = element("a", "bp_relation_preview_label");
    previewLabel.hidden = true;
    heading.appendChild(previewLabel);
    preview.appendChild(heading);
    preview.appendChild(element("div", "bp_relation_preview_body"));
    body.appendChild(list);
    body.appendChild(preview);

    const surface = previewUtils.createPreviewSurface({
      panel: panel,
      titleSelector: ".bp_relation_preview_title",
      headerLabelSelector: ".bp_relation_preview_label",
      bodySelector: ".bp_relation_preview_body",
      defaults: { mode: mode, placement: "anchored" },
      onClose: close
    });
    panel.addEventListener("mouseenter", cancelHide);
    if (mode === "hover") panel.addEventListener("mouseleave", scheduleHide);
    return { panel: panel, surface: surface };
  }

  function selectedRow() {
    return rows.find(function (row) { return row.active && !row.current; }) ||
      rows.find(function (row) { return !row.current; }) ||
      null;
  }

  async function activate(row) {
    if (!view || !row || row.current) return;
    const token = ++requestToken;
    rows.forEach(function (other) {
      other.active = other === row;
      other.element.classList.toggle("bp_relation_item_active", other === row);
    });
    const renderOptions = { hydrate: false, renderMath: false };
    view.surface.replaceBody({
      heading: row.title,
      source: row.element,
      html: row.previewKey
        ? loadingHtml
        : previewUtils.previewMessageHtml(relationPreviewDiagnosticOptions(
            "This block has no rendered preview."
          )),
      renderOptions: renderOptions
    });
    if (!row.previewKey) return;
    await previewUtils.renderPreviewIntoSurface(view.surface, row.previewKey, {
      heading: row.title,
      renderOptions: {},
      loadingRenderOptions: renderOptions,
      diagnosticRenderOptions: renderOptions,
      shouldRender: function () { return token === requestToken && isOpen(); },
      fallbackDiagnostic: relationPreviewDiagnosticOptions(),
      semanticOnlyDiagnostic: relationPreviewDiagnosticOptions(
        "This block has no rendered preview."
      ),
      exceptionDiagnostic: relationPreviewDiagnosticOptions(
        "The preview cache content could not be loaded. Refresh the page, or rebuild the site if this persists."
      )
    });
  }

  function onOutsidePointer(ev) {
    if (!withinPopup(ev.target)) close();
  }

  function onKeydown(ev) {
    if (ev.key !== "Escape") return;
    const hadFocus = view && view.panel.contains(document.activeElement);
    close();
    if (hadFocus) chip.focus();
  }

  function open(pin) {
    cancelHide();
    if (!view) view = buildView();
    if (pin) pinned = true;
    view.surface.setBehavior({ mode: pinned ? "pinned" : mode, placement: "anchored" });
    if (isOpen()) return;
    view.panel.hidden = false;
    if (!inSlide) view.surface.position(chip);
    chip.setAttribute("aria-expanded", "true");
    wrap.classList.add("bp_relation_wrap_open");
    document.addEventListener("pointerdown", onOutsidePointer, true);
    document.addEventListener("keydown", onKeydown);
    activate(selectedRow());
  }

  function close() {
    cancelHide();
    pinned = false;
    requestToken += 1;
    if (!isOpen()) return;
    view.panel.hidden = true;
    view.surface.setBehavior({ mode: mode, placement: "anchored" });
    if (!inSlide) view.surface.position(null);
    chip.setAttribute("aria-expanded", "false");
    wrap.classList.remove("bp_relation_wrap_open");
    document.removeEventListener("pointerdown", onOutsidePointer, true);
    document.removeEventListener("keydown", onKeydown);
  }

  chip.addEventListener("click", function (ev) {
    ev.preventDefault();
    if (isOpen() && pinned) {
      close();
    } else {
      open(true);
    }
  });
  if (mode === "hover") {
    chip.addEventListener("mouseenter", function () { open(false); });
    chip.addEventListener("mouseleave", scheduleHide);
  }
}

export function bindAllRelationPanels(previewUtils, root) {
  if (!(root instanceof Element || root instanceof Document)) return;
  root.querySelectorAll(".bp_relation_wrap").forEach(function (wrap) {
    bindRelationPanel(previewUtils, wrap);
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
