(function () {
  const { blueprintDataUrl, loadPreviewApi, onDomReady } = createBlueprintPreviewApiLoader(window);

  function setText(root, selector, text) {
    const node = root.querySelector(selector);
    if (node) node.textContent = text;
  }

  function appendTextNode(parent, tagName, className, text) {
    const node = document.createElement(tagName);
    if (className) node.className = className;
    node.textContent = text;
    parent.appendChild(node);
    return node;
  }

  function appendFact(parent, label, value) {
    if (value === null || typeof value === "undefined" || value === "" || value === 0) return;
    const fact = appendTextNode(parent, "span", "bp_custom_render_client_fact", "");
    appendTextNode(fact, "strong", "", label);
    fact.appendChild(document.createTextNode(" " + value));
  }

  function appendPreviewMeta(parent, text) {
    if (!text) return;
    appendTextNode(parent, "span", "", text);
  }

  function previewKeyFor(api, example) {
    return api.previewKey(example.dataset.bpPreviewLabel, example.dataset.bpPreviewFacet);
  }

  function expectedOk(example) {
    return example.dataset.bpExpectOk !== "false";
  }

  function writeResultAttrs(example, result) {
    example.dataset.bpPreviewKey = result.key || "";
    example.dataset.bpRenderOk = result.ok ? "true" : "false";
    example.dataset.bpExpectedOk = expectedOk(example) ? "true" : "false";
    example.dataset.bpRenderReason = result.reason || "";
    example.dataset.bpRenderMode = result.renderMode || "";
    example.dataset.bpCanonicalPreview = result.canonicalHtml ? "true" : "false";
    example.dataset.bpCanonicalSourceHref = result.canonicalSourceHref || "";
    if (result.externalMarkup) {
      example.dataset.bpExternalMarkupLanguage = result.externalMarkup.language || "";
      example.dataset.bpExternalMarkupSlot = result.externalMarkup.slot || "";
      example.dataset.bpExternalMarkupHasLocation = result.externalMarkup.location ? "true" : "false";
    }
    if (result.manifestEntry) {
      example.dataset.bpManifestLabel = result.manifestEntry.label || "";
      example.dataset.bpManifestFacet = result.manifestEntry.facet || "";
      example.dataset.bpManifestHref = result.manifestEntry.href || "";
      example.dataset.bpManifestTitle = result.manifestEntry.title || "";
    }
  }

  function renderPreviewHeader(example, result) {
    const target = example.querySelector("[data-bp-custom-client-preview-header]");
    if (!target) return;
    target.replaceChildren();
    if (example.dataset.bpCustomClientExample === "render-canonical-preview-into" && result.ok) {
      target.hidden = true;
      return;
    }
    target.hidden = false;
    const entry = result.manifestEntry;
    if (!entry) {
      appendTextNode(
        target,
        "div",
        "bp_custom_render_client_preview_title",
        result.key || "Preview unavailable"
      );
      appendTextNode(
        target,
        "div",
        "bp_custom_render_client_preview_meta",
        result.reason || "not available"
      );
      return;
    }

    const title = document.createElement(entry.href ? "a" : "span");
    title.className = "bp_custom_render_client_preview_title";
    title.textContent = entry.title || result.key;
    if (entry.href) title.href = entry.href;
    target.appendChild(title);

    const meta = appendTextNode(target, "div", "bp_custom_render_client_preview_meta", "");
    appendPreviewMeta(meta, entry.kind);
    appendPreviewMeta(meta, entry.facet ? "facet " + entry.facet : "");
    appendTextNode(meta, "code", "", result.key || "");
  }

  function renderManifestSummary(example, result) {
    const target = example.querySelector("[data-bp-custom-client-summary]");
    if (!target) return;
    target.replaceChildren();
    if (example.dataset.bpCustomClientExample === "render-canonical-preview-into" && result.ok) {
      target.hidden = true;
      return;
    }
    target.hidden = false;
    if (!result.ok && !result.manifestEntry) {
      appendFact(target, "Status", result.reason || "not available");
      return;
    }
    const entry = result.manifestEntry;
    if (!entry) return;
    const facts = appendTextNode(target, "div", "bp_custom_render_client_facts", "");
    appendFact(facts, "Key", result.key);
    appendFact(facts, "Kind", entry.kind);
    appendFact(facts, "Facet", entry.facet);
    appendFact(facts, "Label", entry.label);
    appendFact(facts, "Group", entry.group ? entry.group.title : "");
    appendFact(facts, "Statement uses", Array.isArray(entry.statementUses) ? entry.statementUses.length : 0);
    appendFact(facts, "Proof uses", Array.isArray(entry.proofUses) ? entry.proofUses.length : 0);
    appendFact(facts, "Used by", Array.isArray(entry.usedBy) ? entry.usedBy.length : 0);
    appendFact(facts, "Code previews", Array.isArray(entry.leanCodePreviewKeys) ? entry.leanCodePreviewKeys.length : 0);
    appendFact(facts, "External markup", Array.isArray(entry.externalMarkup) ? entry.externalMarkup.length : 0);
  }

  function appendMarkdownInline(parent, text) {
    String(text || "").split(/(\*\*[^*]+\*\*)/g).forEach(function (part) {
      if (!part) return;
      if (part.startsWith("**") && part.endsWith("**") && part.length > 4) {
        appendTextNode(parent, "strong", "", part.slice(2, -2));
      } else {
        parent.appendChild(document.createTextNode(part));
      }
    });
  }

  async function renderMarkdownFallback(payload, target) {
    const article = document.createElement("article");
    article.className = "bp_custom_render_client_external";
    appendTextNode(article, "div", "bp_custom_render_client_external_kicker", "Markdown fallback");
    const lines = String(payload.raw || "").split(/\n+/).map(function (line) {
      return line.trim();
    }).filter(Boolean);
    lines.forEach(function (line) {
      if (line.startsWith("# ")) {
        appendTextNode(article, "h4", "", line.slice(2).trim());
      } else {
        const paragraph = document.createElement("p");
        appendMarkdownInline(paragraph, line);
        article.appendChild(paragraph);
      }
    });
    appendFact(
      article,
      "Source",
      (payload.language || "markup") + "/" + (payload.slot || "default")
    );
    target.replaceChildren(article);
  }

  function graphSampleNodes(graph) {
    if (!graph || !Array.isArray(graph.nodes)) return [];
    const preferred = ["used_target", "used_grouped_proof_panel", "preview_final"];
    const selected = [];
    preferred.forEach(function (label) {
      const node = graph.nodes.find(function (node) { return node && node.label === label; });
      if (node && !selected.includes(node)) selected.push(node);
    });
    graph.nodes.forEach(function (node) {
      if (selected.length >= 5) return;
      if (node && !selected.includes(node)) selected.push(node);
    });
    return selected;
  }

  function renderGraphNodeLink(parent, node) {
    const tagName = node && node.href ? "a" : "span";
    const item = appendTextNode(
      parent,
      tagName,
      "bp_custom_render_client_graph_node",
      node && node.title ? node.title : (node && node.label ? node.label : "node")
    );
    if (tagName === "a") item.href = node.href;
    if (node && node.label) item.dataset.bpGraphNodeLabel = node.label;
    return item;
  }

  async function renderGraphData(api, root) {
    const card = root.querySelector("[data-bp-custom-client-graph]");
    if (!card) return { ok: true };
    const summary = card.querySelector("[data-bp-custom-client-graph-summary]");
    const nodesTarget = card.querySelector("[data-bp-custom-client-graph-nodes]");
    if (summary) summary.replaceChildren();
    if (nodesTarget) nodesTarget.replaceChildren();
    const graphModuleUrl =
      api && typeof api.graphApiModuleUrl === "function"
        ? api.graphApiModuleUrl()
        : api && typeof api.dataUrl === "function"
          ? api.dataUrl("api/graph.mjs")
        : blueprintDataUrl("api/graph.mjs");
    const graphModule = await import(graphModuleUrl);
    const graphs = typeof graphModule.loadGraphs === "function" ? await graphModule.loadGraphs() : [];
    const graph = graphs[0] || null;
    card.dataset.bpGraphOk = graph ? "true" : "false";
    card.dataset.bpGraphCount = String(graphs.length);
    card.dataset.bpGraphKey = graph && graph.key ? graph.key : "";
    card.dataset.bpGraphNodeCount = graph && Array.isArray(graph.nodes) ? String(graph.nodes.length) : "0";
    card.dataset.bpGraphEdgeCount = graph && Array.isArray(graph.edges) ? String(graph.edges.length) : "0";
    card.dataset.bpGraphGroupCount = graph && Array.isArray(graph.groups) ? String(graph.groups.length) : "0";
    if (!graph) {
      if (summary) appendFact(summary, "Status", "no graph data");
      return { ok: false };
    }
    if (summary) {
      const facts = appendTextNode(summary, "div", "bp_custom_render_client_facts", "");
      appendFact(facts, "Graphs", graphs.length);
      appendFact(facts, "Key", graph.key);
      appendFact(facts, "Nodes", graph.nodes.length);
      appendFact(facts, "Edges", graph.edges.length);
      appendFact(facts, "Groups", graph.groups.length);
    }
    if (nodesTarget) {
      graphSampleNodes(graph).forEach(function (node) {
        renderGraphNodeLink(nodesTarget, node);
      });
    }
    return { ok: true, graph: graph, graphs: graphs };
  }

  async function renderExample(api, example) {
    const body = example.querySelector("[data-bp-custom-client-body]");
    if (!body) return null;
    const key = previewKeyFor(api, example);
    const exampleName = example.dataset.bpCustomClientExample;
    let result;
    if (exampleName === "render-preview-into") {
      result = await api.renderPreviewInto(body, key);
    } else if (exampleName === "render-canonical-preview-into") {
      result = await api.renderCanonicalPreviewInto(body, key);
    } else if (exampleName === "render-node") {
      result = await api.renderNode(body, {
        label: example.dataset.bpPreviewLabel,
        facet: example.dataset.bpPreviewFacet,
        externalMarkup: {
          prefer: [
            { language: "markdown", slot: "original", render: renderMarkdownFallback },
            { display: "source" }
          ]
        }
      });
    } else {
      throw new Error("Unknown custom render client example: " + exampleName);
    }
    writeResultAttrs(example, result);
    renderPreviewHeader(example, result);
    renderManifestSummary(example, result);
    return result;
  }

  async function bindClient(api, root) {
    if (!(root instanceof HTMLElement)) return;
    if (root.dataset.bpCustomClientBound === "true") return;
    root.dataset.bpCustomClientBound = "true";
    root.dataset.bpCustomClientStatus = "loading";
    setText(root, "[data-bp-custom-client-status-text]", "Loading");
    try {
      const examples = Array.from(root.querySelectorAll("[data-bp-custom-client-example]"));
      if (examples.length === 0) {
        throw new Error("Custom render client root has no preview examples");
      }
      const results = await Promise.all(examples.map(function (example) {
        return renderExample(api, example);
      }));
      const graphResult = await renderGraphData(api, root);
      const ok = results.every(function (result, index) {
        return result && result.ok === expectedOk(examples[index]);
      }) && graphResult.ok;
      root.dataset.bpCustomClientStatus = ok ? "ready" : "error";
      setText(root, "[data-bp-custom-client-status-text]", ok ? "Ready" : "Incomplete");
    } catch (err) {
      root.dataset.bpCustomClientStatus = "error";
      root.dataset.bpCustomClientError = err && err.message ? err.message : String(err);
      setText(root, "[data-bp-custom-client-status-text]", "Error");
    }
  }

  function bindAll(api) {
    document.querySelectorAll("[data-bp-custom-render-client]").forEach(function (root) {
      bindClient(api, root);
    });
  }

  function reportLoadError(err) {
    document.querySelectorAll("[data-bp-custom-render-client]").forEach(function (root) {
      if (!(root instanceof HTMLElement)) return;
      root.dataset.bpCustomClientStatus = "error";
      root.dataset.bpCustomClientError = err && err.message ? err.message : String(err);
      setText(root, "[data-bp-custom-client-status-text]", "Error");
    });
  }

  loadPreviewApi().then(function (api) {
    onDomReady(function () {
      bindAll(api);
    });
  }).catch(function (err) {
    onDomReady(function () {
      reportLoadError(err);
    });
  });
})();
