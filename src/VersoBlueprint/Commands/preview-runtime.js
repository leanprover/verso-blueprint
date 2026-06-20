(function () {
  if (window.VersoBlueprint && window.VersoBlueprint.render) return;

  // Runtime-local registries. Keep these private and expose behavior through
  // the render API instead of growing new window globals.
  const previewHydrators = new Map();

  // Runtime-local diagnostics and page-local template capture.

  function previewDebugEnabled() {
    try {
      return window.localStorage.getItem("bp-debug-preview") === "1";
    } catch (_err) {
      return false;
    }
  }

  function previewDebugLabel(node) {
    if (!(node instanceof Element)) return String(node);
    const parts = [node.tagName.toLowerCase()];
    const cls = (node.getAttribute("class") || "").trim();
    const pid = (node.getAttribute("data-bp-preview-id") || "").trim();
    const pkey = (node.getAttribute("data-bp-preview-key") || "").trim();
    const title = (node.getAttribute("data-bp-preview-title") || "").trim();
    if (cls) parts.push("." + cls.replaceAll(" ", "."));
    if (pid) parts.push("pid=" + pid);
    if (pkey) parts.push("pkey=" + pkey);
    if (title) parts.push("title=" + title);
    return parts.join(" ");
  }

  function previewDebug(eventName, payload) {
    if (!previewDebugEnabled()) return;
    try {
      console.log("[bp-preview]", eventName, payload || {});
    } catch (_err) {}
  }

  function collectPreviewTemplates(root, selector, keyAttr) {
    const map = new Map();
    if (!(root instanceof Element || root instanceof Document)) return map;
    if (typeof selector !== "string" || selector.length === 0) return map;
    const keyName =
      typeof keyAttr === "string" && keyAttr.length > 0
        ? keyAttr
        : "data-bp-preview-label";
    root.querySelectorAll(selector).forEach(function (tpl) {
      if (!(tpl instanceof Element)) return;
      const label = tpl.getAttribute(keyName) || "";
      let html = "";
      if (tpl instanceof HTMLTemplateElement) {
        const content = tpl.content.cloneNode(true);
        if (content instanceof DocumentFragment) {
          const wrapper = document.createElement("div");
          wrapper.appendChild(content);
          html = (wrapper.innerHTML || "").trim();
        }
      }
      if (!html) {
        html = (tpl.innerHTML || "").trim();
      }
      if (label && html) {
        map.set(label, html);
      }
    });
    return map;
  }

  function readHtml(entry) {
    if (typeof entry === "string") {
      return entry;
    }
    if (entry && typeof entry === "object" && typeof entry.html === "string") {
      return entry.html;
    }
    return "";
  }

  function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  // Generated-data URL helpers and graph delegation.

  function blueprintGraphApi() {
    return window.bpGraphApi && typeof window.bpGraphApi === "object" ? window.bpGraphApi : null;
  }

  function callBlueprintGraphApi(name, args, fallback) {
    const api = blueprintGraphApi();
    const method = api && api[name];
    if (typeof method === "function") {
      return method.apply(api, args);
    }
    if (typeof fallback === "function") {
      return fallback();
    }
    return fallback;
  }

  function blueprintDataUrl(filename) {
    return callBlueprintGraphApi("dataUrl", [filename], function () {
      const safeFilename = String(filename || "").trim();
      return safeFilename ? "-verso-data/" + safeFilename : "-verso-data/";
    });
  }

  function fetchBlueprintJson(url) {
    return fetch(url).then(function (resp) {
      if (!resp.ok) {
        throw new Error("HTTP " + resp.status + " while loading " + url);
      }
      return resp.json();
    });
  }

  function decodeBlueprintKeyedEntries(data, spec) {
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new Error(spec.objectMessage);
    }
    const entries = data[spec.arrayField];
    if (!Array.isArray(entries)) {
      throw new Error(spec.missingArrayMessage);
    }
    const map = new Map();
    entries.forEach(function (entry, index) {
      if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
        throw new Error(spec.entryName + " " + index + " must be an object");
      }
      const key = typeof entry.key === "string" ? entry.key.trim() : "";
      if (!key) {
        throw new Error(spec.entryName + " " + index + " is missing key");
      }
      if (typeof spec.validateEntry === "function") {
        spec.validateEntry(entry, index);
      }
      if (map.has(key)) {
        throw new Error(spec.duplicateMessage + key);
      }
      map.set(key, entry);
    });
    return map;
  }

  function decodeBlueprintManifest(data) {
    return decodeBlueprintKeyedEntries(data, {
      arrayField: "previews",
      objectMessage: "Blueprint manifest must be an object with a previews array",
      missingArrayMessage: "Blueprint manifest is missing previews array",
      entryName: "Blueprint manifest entry",
      duplicateMessage: "Blueprint manifest contains duplicate key "
    });
  }

  function decodeBlueprintHtmlCache(data) {
    return decodeBlueprintKeyedEntries(data, {
      arrayField: "entries",
      objectMessage: "Blueprint HTML cache must be an object with an entries array",
      missingArrayMessage: "Blueprint HTML cache is missing entries array",
      entryName: "Blueprint HTML cache entry",
      duplicateMessage: "Blueprint HTML cache contains duplicate key ",
      validateEntry: function (entry, index) {
        if (typeof entry.html !== "string") {
          throw new Error("Blueprint HTML cache entry " + index + " is missing html");
        }
        if (!entry.html.trim()) {
          throw new Error("Blueprint HTML cache entry " + index + " has empty html");
        }
      }
    });
  }

  function blueprintManifestUrl() {
    return blueprintDataUrl("blueprint-manifest.json");
  }

  function graphApiModuleUrl() {
    return blueprintDataUrl("api/graph.mjs");
  }

  function previewApiModuleUrl() {
    return blueprintDataUrl("api/preview.mjs");
  }

  function graphDataFromManifest(manifest) {
    return callBlueprintGraphApi("graphsFromManifest", [manifest], []);
  }

  function collectGraphData(root) {
    return callBlueprintGraphApi("getGraphData", [root], null);
  }

  function collectGraphVariants(root) {
    return callBlueprintGraphApi("getGraphVariants", [root], []);
  }

  function loadManifestGraphs(url, options) {
    const manifestUrl = typeof url === "string" && url.trim() ? url : blueprintManifestUrl();
    return callBlueprintGraphApi("loadManifestGraphs", [manifestUrl, options], function () {
      return Promise.reject(new Error("Blueprint graph API unavailable"));
    });
  }

  function loadBlueprintGraphs(options) {
    return callBlueprintGraphApi("loadGraphs", [options], function () {
      return loadManifestGraphs(blueprintManifestUrl(), options);
    });
  }

  // Manifest/cache status, loading, and diagnostics.

  function missingPreviewKeyDiagnosticHtml() {
    return (
      "<div class=\"bp_html_cache_preview_notice\">" +
      "<p><strong>Preview key missing.</strong></p>" +
      "<p>Provide a manifest/cache preview key such as " +
      "<code>some_label--statement</code> or <code>some_label--proof</code>.</p>" +
      "</div>"
    );
  }

  function blueprintHtmlCacheUrl() {
    return blueprintDataUrl("blueprint-html-cache.json");
  }

  const canonicalPreviewDocuments = new Map();
  const canonicalPreviewHtmlByKey = new Map();

  const blueprintManifestStore = {
    status: null,
    map: null,
    promise: null,
    url: blueprintManifestUrl,
    decode: decodeBlueprintManifest,
    debugLabel: "manifest.loadFailed",
    consoleLabel: "Blueprint manifest",
    unavailableTitle: "Preview manifest unavailable.",
    requiredFilename: "blueprint-manifest.json",
    missingTitle: "Preview entry missing from manifest.",
    missingReadyText: "The site emitted a Blueprint manifest, but this preview key was not present."
  };

  const blueprintHtmlCacheStore = {
    status: null,
    map: null,
    promise: null,
    url: blueprintHtmlCacheUrl,
    decode: decodeBlueprintHtmlCache,
    debugLabel: "htmlCache.loadFailed",
    consoleLabel: "Blueprint HTML cache",
    unavailableTitle: "Preview HTML cache unavailable.",
    requiredFilename: "blueprint-html-cache.json",
    missingTitle: "Preview entry missing from HTML cache.",
    missingReadyText: "The site emitted a rendered-fragment cache, but this preview key was not present."
  };

  function defaultBlueprintStoreStatus(store) {
    return {
      state: "idle",
      attempts: 0,
      url: store.url(),
      lastError: "",
      entryCount: 0
    };
  }

  function cloneBlueprintStoreStatus(store, status) {
    const fallback = defaultBlueprintStoreStatus(store);
    if (!status || typeof status !== "object") return fallback;
    return {
      state: typeof status.state === "string" ? status.state : fallback.state,
      attempts: Number.isFinite(status.attempts) ? status.attempts : fallback.attempts,
      url: typeof status.url === "string" ? status.url : fallback.url,
      lastError: typeof status.lastError === "string" ? status.lastError : fallback.lastError,
      entryCount: Number.isFinite(status.entryCount) ? status.entryCount : fallback.entryCount
    };
  }

  function readBlueprintStoreStatus(store) {
    return cloneBlueprintStoreStatus(store, store.status);
  }

  function setBlueprintStoreStatus(store, status) {
    store.status = status;
    return status;
  }

  function readBlueprintManifestStatus() {
    return readBlueprintStoreStatus(blueprintManifestStore);
  }

  function readBlueprintHtmlCacheStatus() {
    return readBlueprintStoreStatus(blueprintHtmlCacheStore);
  }

  function blueprintStoreDiagnosticHtml(store, previewKey) {
    const status = readBlueprintStoreStatus(store);
    const trimmedKey = typeof previewKey === "string" ? previewKey.trim() : "";
    const keyHtml = trimmedKey ? "<code>" + escapeHtml(trimmedKey) + "</code>" : "this preview";
    if (status.state === "error") {
      const errorHtml = status.lastError
        ? "<p>Last load error: <code>" + escapeHtml(status.lastError) + "</code></p>"
        : "";
      return (
        "<div class=\"bp_html_cache_preview_notice\">" +
        "<p><strong>" + store.unavailableTitle + "</strong></p>" +
        "<p>Blueprint previews require <code>-verso-data/" + store.requiredFilename + "</code>. " +
        "Rebuild the site or retry after the current build finishes.</p>" +
        "<p>Requested preview: " + keyHtml + "</p>" +
        errorHtml +
        "</div>"
      );
    }
    if (status.state === "ready" && trimmedKey) {
      return (
        "<div class=\"bp_html_cache_preview_notice\">" +
        "<p><strong>" + store.missingTitle + "</strong></p>" +
        "<p>Requested preview: " + keyHtml + "</p>" +
        "<p>" + store.missingReadyText + "</p>" +
        "</div>"
      );
    }
    return "";
  }

  function blueprintManifestDiagnosticHtml(previewKey) {
    return blueprintStoreDiagnosticHtml(blueprintManifestStore, previewKey);
  }

  function blueprintHtmlCacheDiagnosticHtml(previewKey) {
    return blueprintStoreDiagnosticHtml(blueprintHtmlCacheStore, previewKey);
  }

  function fetchBlueprintStoreData(store) {
    const jsonUrl = store.url();
    return fetchBlueprintJson(jsonUrl).then(function (data) {
      return { data: data, url: jsonUrl };
    });
  }

  function loadBlueprintStore(store) {
    const existing = store.map;
    if (existing instanceof Map) {
      return Promise.resolve(existing);
    }
    const existingPromise = store.promise;
    if (existingPromise) {
      return existingPromise;
    }
    const url = store.url();
    const previousStatus = readBlueprintStoreStatus(store);
    const attempts =
      Number.isFinite(previousStatus.attempts) ? previousStatus.attempts + 1 : 1;
    setBlueprintStoreStatus(store, {
      state: "loading",
      attempts: attempts,
      url: url,
      lastError: "",
      entryCount: 0
    });
    let promise = null;
    promise = fetchBlueprintStoreData(store)
      .then(function (result) {
        const map = store.decode(result.data);
        store.map = map;
        setBlueprintStoreStatus(store, {
          state: "ready",
          attempts: attempts,
          url: result.url,
          lastError: "",
          entryCount: map.size
        });
        return map;
      })
      .catch(function (err) {
        const message =
          err && typeof err.message === "string" && err.message.length > 0
            ? err.message
            : String(err);
        store.map = null;
        setBlueprintStoreStatus(store, {
          state: "error",
          attempts: attempts,
          url: url,
          lastError: message,
          entryCount: 0
        });
        previewDebug(store.debugLabel, {
          url: url,
          attempts: attempts,
          error: message
        });
        try {
          console.error("[bp-preview] " + store.consoleLabel + " load failed", {
            url: url,
            error: message
          });
        } catch (_consoleErr) {}
        return new Map();
      })
      .then(function (map) {
        if (store.promise === promise) {
          store.promise = null;
        }
        return map;
      });
    store.promise = promise;
    return promise;
  }

  function loadBlueprintManifest() {
    return loadBlueprintStore(blueprintManifestStore);
  }

  function loadBlueprintHtmlCache() {
    return loadBlueprintStore(blueprintHtmlCacheStore);
  }

  function readBlueprintStoreEntry(store, previewKey) {
    if (typeof previewKey !== "string" || previewKey.length === 0) return null;
    const map = store.map;
    if (!(map instanceof Map)) return null;
    return map.get(previewKey) || null;
  }

  function previewKey(label, facet) {
    const trimmedLabel = typeof label === "string" ? label.trim() : "";
    if (!trimmedLabel) return "";
    const trimmedFacet = typeof facet === "string" && facet.trim() ? facet.trim() : "statement";
    return trimmedLabel + "--" + trimmedFacet;
  }

  function statementPreviewKey(label) {
    return previewKey(label, "statement");
  }

  // Preview resolution joins semantic manifest entries with opaque body fragments.
  //
  // The HTML cache is presentation data. Runtime code may insert and hydrate
  // its fragments, but semantic facts must come from the manifest entry. If a
  // future client needs another fact, add it to the manifest instead of parsing
  // cached HTML.

  async function loadBlueprintStoreEntry(store, previewKey) {
    const exact = readBlueprintStoreEntry(store, previewKey);
    if (exact) return exact;
    const entryMap = await loadBlueprintStore(store);
    if (!(entryMap instanceof Map)) return null;
    if (typeof previewKey === "string" && previewKey.length > 0 && entryMap.has(previewKey)) {
      return entryMap.get(previewKey) || null;
    }
    return null;
  }

  async function loadBlueprintManifestEntry(previewKey) {
    return loadBlueprintStoreEntry(blueprintManifestStore, previewKey);
  }

  async function loadBlueprintHtmlCacheEntry(previewKey) {
    return loadBlueprintStoreEntry(blueprintHtmlCacheStore, previewKey);
  }

  async function resolveBlueprintPreview(previewKey) {
    const key = typeof previewKey === "string" ? previewKey.trim() : "";
    if (!key) {
      return {
        ok: false,
        key: "",
        reason: "missing-key",
        manifestEntry: null,
        htmlCacheEntry: null,
        html: "",
        diagnosticHtml: missingPreviewKeyDiagnosticHtml()
      };
    }
    const results = await Promise.all([
      loadBlueprintManifestEntry(key),
      loadBlueprintHtmlCacheEntry(key)
    ]);
    const manifestEntry = results[0] || null;
    const htmlCacheEntry = results[1] || null;
    const html = readHtml(htmlCacheEntry);
    if (!manifestEntry) {
      return {
        ok: false,
        key: key,
        reason: "manifest-entry-missing",
        manifestEntry: null,
        htmlCacheEntry: htmlCacheEntry,
        html: "",
        diagnosticHtml: blueprintManifestDiagnosticHtml(key)
      };
    }
    if (!html) {
      return {
        ok: false,
        key: key,
        reason: "html-cache-entry-missing",
        manifestEntry: manifestEntry,
        htmlCacheEntry: htmlCacheEntry,
        html: "",
        diagnosticHtml: blueprintHtmlCacheDiagnosticHtml(key)
      };
    }
    return {
      ok: true,
      key: key,
      reason: "",
      manifestEntry: manifestEntry,
      htmlCacheEntry: htmlCacheEntry,
      html: html,
      diagnosticHtml: ""
    };
  }

  // Rendered-fragment insertion and hydration.

  function hydrateRenderedPreview(root, options) {
    const opts = options && typeof options === "object" ? options : {};
    if (!(root instanceof Element || root instanceof Document)) return false;
    if (opts.hydrate !== false) {
      bindTemplatePreviewDescriptors(root);
      runPreviewHydrators(root);
    }
    if (opts.renderMath !== false) {
      renderBlueprintMath(root);
    }
    return true;
  }

  function renderHtmlInto(target, html, options) {
    if (!(target instanceof Element)) return false;
    const safeHtml = typeof html === "string" ? html : "";
    if (safeHtml.length === 0) {
      target.replaceChildren();
      return true;
    }
    target.innerHTML = safeHtml;
    hydrateRenderedPreview(target, options);
    return true;
  }

  async function renderBlueprintPreviewInto(target, previewKey, options) {
    if (!(target instanceof Element)) {
      throw new Error("renderBlueprintPreviewInto target must be a DOM Element");
    }
    const opts = options && typeof options === "object" ? options : {};
    const result = await resolveBlueprintPreview(previewKey);
    const html = result.ok ? result.html : (opts.diagnostics === false ? "" : result.diagnosticHtml);
    renderHtmlInto(target, html, opts);
    return result;
  }

  // Canonical generated-node rendering.
  //
  // The HTML cache intentionally carries reusable body fragments, not full
  // Blueprint node wrappers. To render the exact Lean-generated shell without
  // duplicating wrapper semantics in JavaScript or emitting a second wrapper
  // cache, follow the manifest href, clone the canonical node, and rebase its
  // links for insertion into the current page.

  function urlWithoutHash(url) {
    const clone = new URL(url.href);
    clone.hash = "";
    return clone.href;
  }

  function currentDocumentUrlWithoutHash() {
    return urlWithoutHash(new URL(window.location.href));
  }

  function canonicalPreviewUrl(entry) {
    if (!entry || typeof entry !== "object" || typeof entry.href !== "string") return null;
    const href = entry.href.trim();
    if (!href) return null;
    try {
      return new URL(href, document.baseURI || window.location.href);
    } catch (_err) {
      return null;
    }
  }

  function canonicalPreviewId(url, result) {
    if (url && typeof url.hash === "string" && url.hash.length > 1) {
      const raw = url.hash.slice(1);
      try {
        return decodeURIComponent(raw);
      } catch (_err) {
        return raw;
      }
    }
    if (result && typeof result.key === "string" && result.key) {
      return "--informal-preview-" + result.key;
    }
    return "";
  }

  function canonicalPreviewDiagnosticHtml(title, detail, previewKey) {
    const keyHtml = previewKey ? "<p>Requested preview: <code>" + escapeHtml(previewKey) + "</code></p>" : "";
    return (
      "<div class=\"bp_html_cache_preview_notice\">" +
      "<p><strong>" + escapeHtml(title) + "</strong></p>" +
      "<p>" + escapeHtml(detail) + "</p>" +
      keyHtml +
      "</div>"
    );
  }

  function canonicalPreviewResult(result, fields) {
    return Object.assign(
      {},
      result || {},
      {
        canonicalHtml: "",
        canonicalSourceHref: ""
      },
      fields || {}
    );
  }

  async function loadCanonicalPreviewDocument(url) {
    const pageUrl = urlWithoutHash(url);
    if (pageUrl === currentDocumentUrlWithoutHash()) {
      return document;
    }
    const existing = canonicalPreviewDocuments.get(pageUrl);
    if (existing) return existing;
    const promise = fetch(pageUrl)
      .then(function (resp) {
        if (!resp.ok) {
          throw new Error("HTTP " + resp.status + " while loading " + pageUrl);
        }
        return resp.text();
      })
      .then(function (html) {
        return new DOMParser().parseFromString(html, "text/html");
      });
    canonicalPreviewDocuments.set(pageUrl, promise);
    return promise;
  }

  function rebaseUrlAttribute(node, attrName, baseUrl) {
    const value = node.getAttribute(attrName);
    if (typeof value !== "string" || !value.trim()) return;
    const trimmed = value.trim();
    const lower = trimmed.toLowerCase();
    if (
      lower.startsWith("javascript:") ||
      lower.startsWith("mailto:") ||
      lower.startsWith("tel:") ||
      lower.startsWith("data:")
    ) return;
    try {
      node.setAttribute(attrName, new URL(trimmed, baseUrl).href);
    } catch (_err) {}
  }

  function forEachMatchingElement(root, selector, callback) {
    if (!(root instanceof Element)) return;
    if (root.matches(selector)) callback(root);
    root.querySelectorAll(selector).forEach(function (node) {
      callback(node);
    });
  }

  function canonicalPreviewDocumentBaseUrl(doc, sourceUrl) {
    const pageUrl = urlWithoutHash(sourceUrl);
    const base = doc instanceof Document ? doc.querySelector("base[href]") : null;
    const href = base instanceof Element ? (base.getAttribute("href") || "").trim() : "";
    if (href.length > 0) {
      try {
        return new URL(href, pageUrl).href;
      } catch (_err) {}
    }
    return pageUrl;
  }

  function rebaseCanonicalPreviewLinks(root, baseUrl) {
    forEachMatchingElement(root, "[href]", function (node) {
      rebaseUrlAttribute(node, "href", baseUrl);
    });
    forEachMatchingElement(root, "[src]", function (node) {
      rebaseUrlAttribute(node, "src", baseUrl);
    });
    forEachMatchingElement(root, "[data-bp-preview-header-href]", function (node) {
      rebaseUrlAttribute(node, "data-bp-preview-header-href", baseUrl);
    });
  }

  async function resolveCanonicalBlueprintPreview(previewKey) {
    const result = await resolveBlueprintPreview(previewKey);
    if (!result.ok) {
      return canonicalPreviewResult(result);
    }
    const cached = canonicalPreviewHtmlByKey.get(result.key);
    if (cached) {
      return canonicalPreviewResult(result, {
        canonicalHtml: cached.html,
        canonicalSourceHref: cached.href
      });
    }
    const url = canonicalPreviewUrl(result.manifestEntry);
    if (!url) {
      return canonicalPreviewResult(result, {
        ok: false,
        reason: "canonical-href-missing",
        diagnosticHtml: canonicalPreviewDiagnosticHtml(
          "Canonical preview link missing.",
          "The manifest entry did not include a generated-page link for this preview.",
          result.key
        )
      });
    }

    try {
      const doc = await loadCanonicalPreviewDocument(url);
      const id = canonicalPreviewId(url, result);
      const node = id ? doc.getElementById(id) : null;
      if (!(node instanceof Element)) {
        return canonicalPreviewResult(result, {
          ok: false,
          reason: "canonical-preview-node-missing",
          canonicalSourceHref: url.href,
          diagnosticHtml: canonicalPreviewDiagnosticHtml(
            "Canonical preview node missing.",
            "The generated page loaded, but the linked Blueprint node was not present.",
            result.key
          )
        });
      }
      const clone = node.cloneNode(true);
      rebaseCanonicalPreviewLinks(clone, canonicalPreviewDocumentBaseUrl(doc, url));
      const canonical = {
        html: clone.outerHTML,
        href: url.href
      };
      canonicalPreviewHtmlByKey.set(result.key, canonical);
      return canonicalPreviewResult(result, {
        canonicalHtml: canonical.html,
        canonicalSourceHref: canonical.href
      });
    } catch (err) {
      const message = err && err.message ? err.message : String(err);
      return canonicalPreviewResult(result, {
        ok: false,
        reason: "canonical-preview-load-failed",
        canonicalSourceHref: url.href,
        diagnosticHtml: canonicalPreviewDiagnosticHtml(
          "Canonical preview page unavailable.",
          message,
          result.key
        )
      });
    }
  }

  async function renderCanonicalBlueprintPreviewInto(target, previewKey, options) {
    if (!(target instanceof Element)) {
      throw new Error("renderCanonicalBlueprintPreviewInto target must be a DOM Element");
    }
    const opts = options && typeof options === "object" ? options : {};
    const result = await resolveCanonicalBlueprintPreview(previewKey);
    const html = result.ok
      ? result.canonicalHtml
      : (opts.diagnostics === false ? "" : result.diagnosticHtml);
    renderHtmlInto(target, html, opts);
    return result;
  }

  function renderBlueprintMath(root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    if (typeof katex !== "object" || typeof katex.render !== "function") return;
    const resolvePrelude = function (m) {
      if (!(m instanceof Element)) return "";
      const table =
        window.bpTexPreludeTable && typeof window.bpTexPreludeTable === "object"
          ? window.bpTexPreludeTable
          : {};
      const preludeId = (m.getAttribute("data-bp-tex-prelude-id") || "").trim();
      if (preludeId && typeof table[preludeId] === "string") {
        return table[preludeId].trim();
      }
      const fallback = m.getAttribute("data-bp-tex-prelude");
      return typeof fallback === "string" ? fallback.trim() : "";
    };
    const renderAll = function (selector, displayMode) {
      root.querySelectorAll(selector).forEach(function (m) {
        if (!(m instanceof Element)) return;
        if (m.getAttribute("data-bp-math-rendered") === "1") return;
        try {
          const tex = m.textContent || "";
          const prelude = resolvePrelude(m);
          const renderInput = prelude ? prelude + "\n" + tex : tex;
          katex.render(renderInput, m, { throwOnError: false, displayMode: displayMode });
          m.setAttribute("data-bp-math-rendered", "1");
        } catch (_err) {}
      });
    };
    renderAll(".bp_math.inline", false);
    renderAll(".bp_math.display", true);
  }

  // Bundled preview surface and lifecycle helpers.
  //
  // These helpers own browser interaction state for Blueprint's bundled graph,
  // summary, relation-panel, inline-preview, and slide clients. They are not a
  // semantic data layer and are not part of the stable custom-client API unless
  // explicitly re-exported through stableCustomClientApi below.

  function bindCloseOnce(button, onClose) {
    if (!(button instanceof Element)) return;
    if (button.getAttribute("data-bp-bound") === "1") return;
    if (typeof onClose !== "function") return;
    button.setAttribute("data-bp-bound", "1");
    button.addEventListener("click", function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      onClose(ev);
    });
  }

  function bindDismissHandlers(options) {
    const opts = options && typeof options === "object" ? options : {};
    const root = readElementOption(opts, "root", null);
    const trigger = readElementOption(opts, "trigger", null);
    const panel = readElementOption(opts, "panel", null);
    const closeButton = readElementOption(opts, "closeButton", null);
    const owner =
      opts.owner instanceof Element
        ? opts.owner
        : (trigger instanceof Element ? trigger : root);
    const boundAttr = readStringOption(opts, "boundAttr", "data-bp-dismiss-bound");
    const outsideEvent = readStringOption(opts, "outsideEvent", "click");
    const open = readFunctionOption(opts, "open", function () {});
    const close = readFunctionOption(opts, "close", function () {});
    const isOpen = readFunctionOption(opts, "isOpen", function () {
      return panel instanceof Element ? !panel.hidden : true;
    });
    const toggle = readFunctionOption(opts, "toggle", function () {
      if (isOpen()) {
        close();
      } else {
        open();
      }
    });
    const bindTrigger = opts.bindTrigger !== false && trigger instanceof Element;
    const bindOutside = opts.bindOutside !== false && root instanceof Element;
    const bindEscape = opts.bindEscape === true;
    const stopPanelClick = opts.stopPanelClick === true;
    const preventTriggerDefault = opts.preventTriggerDefault !== false;
    const stopTriggerClick = opts.stopTriggerClick !== false;
    const preventCloseDefault = opts.preventCloseDefault !== false;
    const stopCloseClick = opts.stopCloseClick !== false;

    const controller = {
      root: root,
      trigger: trigger,
      panel: panel,
      closeButton: closeButton,
      isOpen: isOpen,
      open: open,
      close: close,
      toggle: toggle
    };

    if (!(owner instanceof Element)) return controller;
    if (owner.getAttribute(boundAttr) === "1") return controller;
    owner.setAttribute(boundAttr, "1");

    if (bindTrigger) {
      trigger.addEventListener("click", function (ev) {
        if (preventTriggerDefault) ev.preventDefault();
        if (stopTriggerClick) ev.stopPropagation();
        toggle(ev);
      });
    }
    if (closeButton instanceof Element) {
      closeButton.addEventListener("click", function (ev) {
        if (preventCloseDefault) ev.preventDefault();
        if (stopCloseClick) ev.stopPropagation();
        close(ev);
      });
    }
    if (stopPanelClick && panel instanceof Element) {
      panel.addEventListener("click", function (ev) {
        ev.stopPropagation();
      });
    }
    if (bindOutside) {
      document.addEventListener(outsideEvent, function (ev) {
        if (!isOpen()) return;
        const target = ev.target;
        if (!(target instanceof Node)) {
          close(ev);
          return;
        }
        if (root.contains(target)) return;
        close(ev);
      });
    }
    if (bindEscape) {
      document.addEventListener("keydown", function (ev) {
        if (ev.key !== "Escape") return;
        if (!isOpen()) return;
        close(ev);
      });
    }

    return controller;
  }

  function bindAnchoredPopover(options) {
    const opts = options && typeof options === "object" ? options : {};
    const root = readElementOption(opts, "root", null);
    const trigger = readElementOption(opts, "trigger", null);
    const panel = readElementOption(opts, "panel", null);
    const closeButton = readElementOption(opts, "close", null);
    const boundAttr = readStringOption(opts, "boundAttr", "data-bp-popover-bound");
    const offset = readNumberOption(opts, "offset", 8);
    const positionPopover = readFunctionOption(opts, "position", function () {
      const rootRect = root.getBoundingClientRect();
      const triggerRect = trigger.getBoundingClientRect();
      const top = Math.max(0, Math.round(triggerRect.bottom - rootRect.top + offset));
      const right = Math.max(0, Math.round(rootRect.right - triggerRect.right));
      panel.style.top = top + "px";
      panel.style.right = right + "px";
    });

    if (!(root instanceof Element) || !(trigger instanceof Element) || !(panel instanceof Element)) {
      return null;
    }

    const controller = {
      root: root,
      trigger: trigger,
      panel: panel,
      closeButton: closeButton,
      isOpen: function () { return !panel.hidden; },
      open: function () { setOpen(true); },
      close: function () { setOpen(false); },
      toggle: function () { setOpen(panel.hidden); },
      position: position,
      setOpen: setOpen
    };

    function position() {
      positionPopover(controller, root, trigger, panel);
    }

    function setOpen(isOpen) {
      const open = !!isOpen;
      if (open) position();
      panel.hidden = !open;
      trigger.setAttribute("aria-expanded", open ? "true" : "false");
    }

    setOpen(false);
    bindDismissHandlers({
      owner: trigger,
      root: root,
      trigger: trigger,
      panel: panel,
      close: controller.close,
      closeButton: closeButton,
      isOpen: controller.isOpen,
      toggle: controller.toggle,
      boundAttr: boundAttr,
      outsideEvent: "pointerdown"
    });

    return controller;
  }

  function readAnchorRect(anchor) {
    if (anchor instanceof Element) {
      return anchor.getBoundingClientRect();
    }
    if (
      anchor &&
      typeof anchor === "object" &&
      Number.isFinite(anchor.left) &&
      Number.isFinite(anchor.right) &&
      Number.isFinite(anchor.top) &&
      Number.isFinite(anchor.bottom)
    ) {
      return anchor;
    }
    return null;
  }

  function positionAnchoredPanel(panel, anchor, margin, offset) {
    if (!(panel instanceof Element)) return;
    const rect = readAnchorRect(anchor);
    if (!rect) return;
    const safeMargin = Number.isFinite(margin) ? margin : 12;
    const safeOffset = Number.isFinite(offset) ? offset : 10;
    const panelRect = panel.getBoundingClientRect();
    const panelWidth = panelRect.width || Math.min(520, window.innerWidth - safeMargin * 2);
    const panelHeight = panelRect.height || Math.min(420, window.innerHeight - safeMargin * 2);
    let left = rect.left;
    if (left + panelWidth > window.innerWidth - safeMargin) {
      left = window.innerWidth - panelWidth - safeMargin;
    }
    left = Math.max(safeMargin, left);
    let top = rect.bottom + safeOffset;
    if (top + panelHeight > window.innerHeight - safeMargin) {
      top = rect.top - panelHeight - safeOffset;
    }
    top = Math.max(safeMargin, top);
    panel.style.left = left + "px";
    panel.style.top = top + "px";
  }

  function bindPanelRepositioner(options) {
    const opts = options && typeof options === "object" ? options : {};
    const owner = readElementOption(opts, "owner", null);
    const boundAttr = readStringOption(opts, "boundAttr", "data-bp-panel-reposition-bound");
    const reposition = readFunctionOption(opts, "reposition", null);
    const bindResize = opts.bindResize !== false;
    const bindScroll = opts.bindScroll !== false;
    if (!reposition) return null;

    const controller = {
      reposition: function () {
        reposition(controller);
      }
    };

    if (owner instanceof Element) {
      if (owner.getAttribute(boundAttr) === "1") return controller;
      owner.setAttribute(boundAttr, "1");
    }
    if (bindResize) window.addEventListener("resize", controller.reposition);
    if (bindScroll) window.addEventListener("scroll", controller.reposition, true);
    return controller;
  }

  function shouldKeepOpen(nextTarget, trigger, panel) {
    if (!(nextTarget instanceof Element)) return false;
    if (trigger instanceof Element && trigger.contains(nextTarget)) return true;
    if (panel instanceof Element && panel.contains(nextTarget)) return true;
    const inlinePanel = document.getElementById("bp-inline-preview-panel");
    if (inlinePanel instanceof Element && inlinePanel.contains(nextTarget)) return true;
    return false;
  }

  function normalizePreviewMode(rawMode, fallback) {
    const defaultMode = fallback === "hover" || fallback === "pinned" ? fallback : "hover";
    const mode = String(rawMode || "").trim().toLowerCase();
    if (mode === "hover") return "hover";
    if (mode === "pinned") return "pinned";
    return defaultMode;
  }

  function normalizePreviewPlacement(rawPlacement, fallback) {
    const defaultPlacement =
      fallback === "anchored" || fallback === "docked" ? fallback : "anchored";
    const placement = String(rawPlacement || "").trim().toLowerCase();
    if (placement === "anchored") return "anchored";
    if (placement === "docked") return "docked";
    return defaultPlacement;
  }

  function readPanelBehavior(panel, defaults) {
    const defaultMode = normalizePreviewMode(defaults && defaults.mode, "hover");
    const defaultPlacement = normalizePreviewPlacement(defaults && defaults.placement, "anchored");
    if (!(panel instanceof Element)) {
      return {
        mode: defaultMode,
        placement: defaultPlacement,
        isPinned: defaultMode === "pinned",
        isHover: defaultMode === "hover",
        isAnchored: defaultPlacement === "anchored",
        isDocked: defaultPlacement === "docked"
      };
    }
    const rawMode = (panel.getAttribute("data-bp-preview-mode") || "").trim();
    const rawPlacement = (panel.getAttribute("data-bp-preview-placement") || "").trim();
    const mode = normalizePreviewMode(rawMode, defaultMode);
    const placement = normalizePreviewPlacement(rawPlacement, defaultPlacement);
    return {
      mode: mode,
      placement: placement,
      isPinned: mode === "pinned",
      isHover: mode === "hover",
      isAnchored: placement === "anchored",
      isDocked: placement === "docked"
    };
  }

  function normalizePanelBehavior(panel, defaults, nextBehavior) {
    const fallback = readPanelBehavior(panel, defaults);
    if (!nextBehavior || typeof nextBehavior !== "object") return fallback;
    const mode = normalizePreviewMode(nextBehavior.mode, fallback.mode);
    const placement = normalizePreviewPlacement(nextBehavior.placement, fallback.placement);
    return {
      mode: mode,
      placement: placement,
      isPinned: mode === "pinned",
      isHover: mode === "hover",
      isAnchored: placement === "anchored",
      isDocked: placement === "docked"
    };
  }

  function resetPanelPosition(panel) {
    if (!(panel instanceof Element)) return;
    panel.style.left = "";
    panel.style.top = "";
  }

  function hidePreviewSurfaces(root) {
    const scope = root instanceof Element || root instanceof Document ? root : document;
    const selector = "#bp-inline-preview-panel, #bp-inline-preview-child-panel, .bp_preview_panel";
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

  function configureCloseButton(closeButton, onClose, behavior) {
    if (!(closeButton instanceof Element)) return;
    const pinned = !!(behavior && behavior.isPinned);
    closeButton.hidden = !pinned;
    closeButton.style.display = pinned ? "" : "none";
    closeButton.setAttribute("aria-hidden", pinned ? "false" : "true");
    closeButton.tabIndex = pinned ? 0 : -1;
    if (!pinned) return;
    bindCloseOnce(closeButton, onClose);
  }

  function pointerWithinPanel(panel, ev) {
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

  function readPanelSlot(panel, selector) {
    if (!(panel instanceof Element)) return null;
    if (typeof selector !== "string" || selector.length === 0) return null;
    const node = panel.querySelector(selector);
    return node instanceof Element ? node : null;
  }

  function readPreviewSurfaceSlots(panel, options) {
    const opts = options && typeof options === "object" ? options : {};
    return {
      panel: panel instanceof Element ? panel : null,
      title: readPanelSlot(panel, readStringOption(opts, "titleSelector", "")),
      headerLabel: readPanelSlot(panel, readStringOption(opts, "headerLabelSelector", "")),
      body: readPanelSlot(panel, readStringOption(opts, "bodySelector", "")),
      footer: readPanelSlot(panel, readStringOption(opts, "footerSelector", "")),
      closeButton: readPanelSlot(panel, readStringOption(opts, "closeSelector", ""))
    };
  }

  function createPreviewSurface(options) {
    const opts = options && typeof options === "object" ? options : {};
    const panel = readElementOption(opts, "panel", null);
    if (!(panel instanceof Element)) return null;
    const slots = readPreviewSurfaceSlots(panel, opts);
    if (!(slots.title instanceof Element) || !(slots.body instanceof Element)) return null;

    const defaults = readObjectOption(opts, "defaults", {});
    const margin = readNumberOption(opts, "margin", 12);
    const offset = readNumberOption(opts, "offset", 10);
    const footerHtmlAttr = readStringOption(opts, "footerHtmlAttr", "");
    const renderFooter = readFunctionOption(opts, "renderFooter", null);
    const onClose = readFunctionOption(opts, "onClose", null);
    const clearBody = readFunctionOption(opts, "clearBody", function (body) {
      body.replaceChildren();
    });
    const renderBody = readFunctionOption(opts, "renderBody", null);
    const positionPanel = readFunctionOption(opts, "positionPanel", null);
    const onHide = readFunctionOption(opts, "onHide", null);
    let triggerLifecycle = null;
    let repositionLifecycle = null;
    let dismissLifecycle = null;

    function renderSurfaceBody(content) {
      const payload = content && typeof content === "object" ? content : {};
      if (renderBody) {
        const bodyPayload = Object.prototype.hasOwnProperty.call(payload, "payload")
          ? payload.payload
          : payload.html;
        renderBody(slots.body, bodyPayload, surface, payload);
        return true;
      }
      const html = typeof payload.html === "string" ? payload.html : "";
      if (html.length === 0 && payload.allowEmpty !== true) return false;
      renderHtmlInto(slots.body, html, readObjectOption(payload, "renderOptions", undefined));
      return true;
    }

    const surface = {
      panel: panel,
      title: slots.title,
      headerLabel: slots.headerLabel,
      body: slots.body,
      footer: slots.footer,
      closeButton: slots.closeButton,
      behavior: normalizePanelBehavior(panel, defaults, null),
      triggerLifecycle: null,
      repositionLifecycle: null,
      dismissLifecycle: null,
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
        setPreviewHeaderLink(slots.headerLabel, sourceNode);
        surface.setFooterSource(sourceNode);
      },
      setFooterSource: function (sourceNode) {
        if (!(slots.footer instanceof Element)) return;
        if (renderFooter) {
          renderFooter(slots.footer, sourceNode, surface);
          return;
        }
        if (!footerHtmlAttr) return;
        const footerHtml =
          sourceNode instanceof Element
            ? (sourceNode.getAttribute(footerHtmlAttr) || "").trim()
            : "";
        if (footerHtml.length > 0) {
          renderHtmlInto(slots.footer, footerHtml);
          slots.footer.hidden = false;
        } else {
          slots.footer.replaceChildren();
          slots.footer.hidden = true;
        }
      },
      clearChrome: function () {
        setPreviewHeaderLink(slots.headerLabel, null);
        surface.setFooterSource(null);
      },
      hideContent: function () {
        panel.hidden = true;
        slots.title.textContent = "";
        clearBody(slots.body);
        surface.clearChrome();
        if (onHide) onHide(surface);
      },
      showContent: function (content) {
        const payload = content && typeof content === "object" ? content : {};
        const behavior =
          payload.behavior && typeof payload.behavior === "object"
            ? surface.setBehavior(payload.behavior)
            : surface.behavior;
        const source = payload.source instanceof Element ? payload.source : payload.anchor;
        if (!renderBody && typeof payload.html !== "string") {
          surface.hideContent();
          return false;
        }
        if (!renderBody && payload.html.length === 0 && payload.allowEmpty !== true) {
          surface.hideContent();
          return false;
        }
        slots.title.textContent = typeof payload.heading === "string" ? payload.heading : "";
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
        const payload = content && typeof content === "object" ? content : {};
        if (payload.behavior && typeof payload.behavior === "object") {
          surface.setBehavior(payload.behavior);
        }
        slots.title.textContent = typeof payload.heading === "string" ? payload.heading : "";
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
          positionAnchoredPanel(
            panel,
            anchor,
            Number.isFinite(opts.margin) ? opts.margin : margin,
            Number.isFinite(opts.offset) ? opts.offset : offset
          );
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
        const triggerOpts =
          triggerOptions && typeof triggerOptions === "object" ? Object.assign({}, triggerOptions) : {};
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
        const repositionOpts =
          repositionOptions && typeof repositionOptions === "object"
            ? Object.assign({}, repositionOptions)
            : {};
        if (!(repositionOpts.owner instanceof Element)) repositionOpts.owner = panel;
        repositionLifecycle = bindPanelRepositioner(repositionOpts);
        surface.repositionLifecycle = repositionLifecycle;
        return repositionLifecycle;
      },
      bindDismissal: function (dismissOptions) {
        const dismissOpts =
          dismissOptions && typeof dismissOptions === "object" ? Object.assign({}, dismissOptions) : {};
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

  function bindPreviewTriggers(options) {
    const opts = options && typeof options === "object" ? options : {};
    const triggerRoot = readRootOption(opts, "triggerRoot", document);
    const eventRoot = readRootOption(opts, "eventRoot", null);
    const panel = readElementOption(opts, "panel", null);
    const triggerSelector = readStringOption(opts, "triggerSelector", "");
    const triggerBoundAttr = readStringOption(
      opts,
      "triggerBoundAttr",
      "data-bp-preview-trigger-bound"
    );
    const eventRootBoundAttr = readStringOption(
      opts,
      "eventRootBoundAttr",
      "data-bp-preview-events-bound"
    );
    const panelBoundAttr = readStringOption(
      opts,
      "panelBoundAttr",
      "data-bp-preview-panel-lifetime-bound"
    );
    const defaults = readObjectOption(opts, "defaults", {});
    const behaviorSource = readObjectOption(opts, "behavior", null);
    const readBehavior = readFunctionOption(opts, "getBehavior", function () {
      return behaviorSource;
    });
    const show = readFunctionOption(opts, "show", function () {});
    const hide = readFunctionOption(opts, "hide", function () {});
    const position = readFunctionOption(opts, "position", function () {});
    const filterTrigger = readFunctionOption(opts, "filterTrigger", function () { return true; });
    const getActiveTrigger = readFunctionOption(opts, "getActiveTrigger", function () {
      return null;
    });
    const getActiveAnchor = readFunctionOption(opts, "getActiveAnchor", getActiveTrigger);
    const resolveTriggerOption = readFunctionOption(opts, "resolveTrigger", null);
    const shouldKeepPreviewOpen = readFunctionOption(opts, "shouldKeepOpen", null);
    const onLeave = readFunctionOption(opts, "onLeave", null);
    const onPanelEnter = readFunctionOption(opts, "onPanelEnter", null);
    const onPanelLeave = readFunctionOption(opts, "onPanelLeave", null);
    const hideDelay = readNumberOption(opts, "hideDelay", 180);
    const bindPanel = opts.bindPanel !== false;
    const bindEscape = opts.bindEscape !== false;
    const bindWindow = opts.bindWindow !== false;
    const activateOnClick = opts.activateOnClick === true;
    const activateOnKeydown = opts.activateOnKeydown === true;
    const enterRequiresHover = opts.enterRequiresHover === true;
    let hideTimer = null;

    function behavior() {
      return normalizePanelBehavior(panel, defaults, readBehavior());
    }

    function cancelHide() {
      if (hideTimer !== null) {
        clearTimeout(hideTimer);
        hideTimer = null;
      }
    }

    function hideNow() {
      cancelHide();
      hide();
    }

    function scheduleHide() {
      cancelHide();
      const current = behavior();
      if (!current.isHover) {
        hideNow();
        return;
      }
      hideTimer = window.setTimeout(function () {
        hideTimer = null;
        hide();
      }, hideDelay);
    }

    const controls = {
      cancelHide: cancelHide,
      scheduleHide: scheduleHide,
      hide: hideNow,
      behavior: behavior
    };

    function resolveTrigger(target, ev) {
      if (resolveTriggerOption) {
        const resolved = resolveTriggerOption(target, ev);
        return resolved instanceof Element ? resolved : null;
      }
      if (!(target instanceof Element)) return null;
      if (!triggerSelector) return target;
      if (target.matches(triggerSelector)) return target;
      const closest = target.closest(triggerSelector);
      return closest instanceof Element ? closest : null;
    }

    function keepOpen(trigger, ev) {
      if (shouldKeepPreviewOpen && shouldKeepPreviewOpen(trigger, ev, controls)) return true;
      return shouldKeepOpen(ev && ev.relatedTarget, trigger, panel);
    }

    function showTrigger(trigger, ev, force) {
      if (!(trigger instanceof Element)) return;
      if (!filterTrigger(trigger, ev, controls)) return;
      if (!force && enterRequiresHover && !behavior().isHover) return;
      cancelHide();
      show(trigger, ev, controls);
    }

    function leaveTrigger(trigger, ev) {
      if (!(trigger instanceof Element)) return;
      if (!filterTrigger(trigger, ev, controls)) return;
      const current = behavior();
      if (!current.isHover) return;
      if (onLeave && onLeave(trigger, ev, controls)) return;
      if (keepOpen(trigger, ev)) return;
      scheduleHide();
    }

    function activateTrigger(trigger, ev) {
      if (!(trigger instanceof Element)) return;
      if (!filterTrigger(trigger, ev, controls)) return;
      const current = behavior();
      if (!current.isPinned) return;
      showTrigger(trigger, ev, true);
      if (ev && typeof ev.preventDefault === "function") ev.preventDefault();
    }

    function bindDirectTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      if (!filterTrigger(trigger, null, controls)) return;
      if (trigger.getAttribute(triggerBoundAttr) === "1") return;
      trigger.setAttribute(triggerBoundAttr, "1");
      trigger.addEventListener("mouseenter", function (ev) {
        showTrigger(trigger, ev);
      });
      trigger.addEventListener("focusin", function (ev) {
        showTrigger(trigger, ev);
      });
      trigger.addEventListener("mouseleave", function (ev) {
        leaveTrigger(trigger, ev);
      });
      trigger.addEventListener("focusout", function (ev) {
        leaveTrigger(trigger, ev);
      });
      if (activateOnClick) {
        trigger.addEventListener("click", function (ev) {
          activateTrigger(trigger, ev);
        });
      }
      if (activateOnKeydown) {
        trigger.addEventListener("keydown", function (ev) {
          if (ev.key !== "Enter" && ev.key !== " ") return;
          activateTrigger(trigger, ev);
        });
      }
    }

    function bindDelegatedRoot(root) {
      if (!(root instanceof Element || root instanceof Document)) return;
      if (root instanceof Element) {
        if (root.getAttribute(eventRootBoundAttr) === "1") return;
        root.setAttribute(eventRootBoundAttr, "1");
      }
      root.addEventListener("mouseover", function (ev) {
        showTrigger(resolveTrigger(ev.target, ev), ev);
      });
      root.addEventListener("focusin", function (ev) {
        showTrigger(resolveTrigger(ev.target, ev), ev);
      });
      root.addEventListener("mouseout", function (ev) {
        leaveTrigger(resolveTrigger(ev.target, ev), ev);
      });
      root.addEventListener("focusout", function (ev) {
        leaveTrigger(resolveTrigger(ev.target, ev), ev);
      });
      if (activateOnClick) {
        root.addEventListener("click", function (ev) {
          activateTrigger(resolveTrigger(ev.target, ev), ev);
        });
      }
      if (activateOnKeydown) {
        root.addEventListener("keydown", function (ev) {
          if (ev.key !== "Enter" && ev.key !== " ") return;
          activateTrigger(resolveTrigger(ev.target, ev), ev);
        });
      }
    }

    function bindPanelLifetime() {
      if (!bindPanel || !(panel instanceof Element)) return;
      if (panel.getAttribute(panelBoundAttr) === "1") return;
      panel.setAttribute(panelBoundAttr, "1");
      const enterPanel = function (ev) {
        cancelHide();
        if (onPanelEnter) onPanelEnter(panel, ev, controls);
      };
      const leavePanel = function (ev) {
        const current = behavior();
        if (!current.isHover) return;
        if (onPanelLeave && onPanelLeave(panel, ev, controls)) return;
        if (shouldKeepOpen(ev && ev.relatedTarget, getActiveAnchor(), panel)) return;
        scheduleHide();
      };
      panel.addEventListener("mouseenter", enterPanel);
      panel.addEventListener("focusin", enterPanel);
      panel.addEventListener("mouseleave", leavePanel);
      panel.addEventListener("focusout", leavePanel);
    }

    function refresh(root) {
      const scope = root instanceof Element || root instanceof Document ? root : triggerRoot;
      if (eventRoot) {
        bindDelegatedRoot(eventRoot);
        return;
      }
      if (!triggerSelector || !(scope instanceof Element || scope instanceof Document)) return;
      if (scope instanceof Element && scope.matches(triggerSelector)) {
        bindDirectTrigger(scope);
      }
      scope.querySelectorAll(triggerSelector).forEach(bindDirectTrigger);
    }

    bindPanelLifetime();
    refresh(triggerRoot);

    if (bindEscape) {
      document.addEventListener("keydown", function (ev) {
        if (ev.key === "Escape") hideNow();
      });
    }
    if (bindWindow) {
      bindPanelRepositioner({
        reposition: function () {
          const current = behavior();
          const activeAnchor = getActiveAnchor();
          if (current.isAnchored && activeAnchor && panel instanceof Element && !panel.hidden) {
            position(activeAnchor);
          }
        }
      });
    }

    return Object.assign(controls, {
      refresh: refresh,
      showTrigger: showTrigger
    });
  }

  // Hydration extension points and option readers.

  function registerPreviewHydrator(name, fn) {
    if (typeof name !== "string" || name.length === 0) return;
    if (typeof fn !== "function") return;
    previewHydrators.set(name, fn);
  }

  function runPreviewHydrators(root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    previewHydrators.forEach(function (fn) {
      if (typeof fn !== "function") return;
      try {
        fn(root);
      } catch (_err) {}
    });
  }

  function readStringOption(options, name, fallback) {
    return options && typeof options[name] === "string" && options[name].length > 0
      ? options[name]
      : fallback;
  }

  function readObjectOption(options, name, fallback) {
    return options && options[name] && typeof options[name] === "object"
      ? options[name]
      : fallback;
  }

  function readNumberOption(options, name, fallback) {
    return options && Number.isFinite(options[name])
      ? options[name]
      : fallback;
  }

  function readFunctionOption(options, name, fallback) {
    return options && typeof options[name] === "function"
      ? options[name]
      : fallback;
  }

  function readElementOption(options, name, fallback) {
    return options && options[name] instanceof Element
      ? options[name]
      : fallback;
  }

  function readRootOption(options, name, fallback) {
    return options && (options[name] instanceof Element || options[name] instanceof Document)
      ? options[name]
      : fallback;
  }

  function createPreviewPanel(options) {
    const opts = options && typeof options === "object" ? options : {};
    const panel = document.createElement("aside");
    const id = readStringOption(opts, "id", "");
    const rootClass = readStringOption(opts, "rootClass", "bp_preview_panel");
    const extraClass = readStringOption(opts, "extraClass", "");
    const mode = normalizePreviewMode(opts.mode, "hover");
    const placement = normalizePreviewPlacement(opts.placement, "anchored");
    const headerClass = readStringOption(opts, "headerClass", "bp_preview_panel_header");
    const headingClass = readStringOption(opts, "headingClass", "");
    const titleClass = readStringOption(opts, "titleClass", "bp_preview_panel_title");
    const headerLabelClass = readStringOption(opts, "headerLabelClass", "");
    const closeClass = readStringOption(opts, "closeClass", "bp_preview_panel_close");
    const closeLabel = readStringOption(opts, "closeLabel", "Close preview");
    const bodyClass = readStringOption(opts, "bodyClass", "bp_preview_panel_body");
    const footerClass = readStringOption(opts, "footerClass", "");
    const parent = opts.parent instanceof Element ? opts.parent : document.body;

    if (id.length > 0) panel.id = id;
    panel.className = rootClass + (extraClass.length > 0 ? " " + extraClass : "");
    panel.setAttribute("data-bp-preview-mode", mode);
    panel.setAttribute("data-bp-preview-placement", placement);
    panel.hidden = true;

    const header = document.createElement("div");
    header.className = headerClass;

    const heading = document.createElement("div");
    if (headingClass.length > 0) heading.className = headingClass;

    const title = document.createElement("div");
    title.className = titleClass;
    heading.appendChild(title);

    if (headerLabelClass.length > 0) {
      const label = document.createElement("a");
      label.className = headerLabelClass;
      label.hidden = true;
      heading.appendChild(label);
    }

    const close = document.createElement("button");
    close.type = "button";
    close.className = closeClass;
    close.setAttribute("aria-label", closeLabel);
    close.textContent = "Close";

    header.appendChild(heading);
    header.appendChild(close);
    panel.appendChild(header);

    const body = document.createElement("div");
    body.className = bodyClass;
    panel.appendChild(body);

    if (footerClass.length > 0) {
      const footer = document.createElement("div");
      footer.className = footerClass;
      footer.hidden = true;
      panel.appendChild(footer);
    }

    if (opts.append !== false && parent instanceof Element) {
      parent.appendChild(panel);
    }
    return panel;
  }

  function previewMessageHtml(options) {
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

  function setPreviewHeaderLink(labelNode, sourceNode) {
    if (!(labelNode instanceof Element)) return;
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

  // Template preview binding adapts the shared helpers to concrete surfaces.

  function bindTemplatePreview(options) {
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
      if (panel instanceof Element) panel.hidden = true;
      return null;
    }
    if (triggers.length === 0) {
      surface.hide();
      return null;
    }
    let activeTrigger = null;
    let showRequestToken = 0;
    let triggerLifecycle = null;

    function hidePanel() {
      if (triggerLifecycle) triggerLifecycle.cancelHide();
      showRequestToken += 1;
      surface.hide();
      activeTrigger = null;
    }

    async function resolveTriggerHtml(trigger, key) {
      const localEntry = previewMap.get(key);
      const localHtml = readHtml(localEntry);
      if (localHtml) return localHtml;
      if (!allowHtmlCache) return "";
      const lookupKey = readLookupKey(trigger, key, localEntry);
      const result = await resolveBlueprintPreview(lookupKey);
      if (result && result.ok) return result.html;
      const diagnosticHtml =
        result && typeof result.diagnosticHtml === "string" ? result.diagnosticHtml : "";
      return diagnosticHtml || blueprintHtmlCacheDiagnosticHtml(lookupKey || key);
    }

    async function showFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      const key = readKey(trigger);
      const requestToken = ++showRequestToken;
      const html = await resolveTriggerHtml(trigger, key);
      if (requestToken !== showRequestToken) return;
      if (!key || !html) {
        hidePanel();
        return;
      }
      activeTrigger = trigger;
      const heading = readTitle(trigger, key);
      surface.showContent({
        heading: heading,
        html: html,
        anchor: trigger
      });
    }

    triggerLifecycle = surface.bindTriggers({
      triggerRoot: triggerRoot,
      triggerSelector: triggerSelector,
      triggerBoundAttr: triggerBoundAttr,
      show: showFromTrigger,
      hide: hidePanel,
      getActiveTrigger: function () { return activeTrigger; }
    });

    return {
      previewMap: previewMap,
      surface: surface,
      behavior: surface.behavior,
      hidePanel: hidePanel,
      showFromTrigger: showFromTrigger
    };
  }

  function readTemplateDescriptorString(root, name, fallback) {
    if (!(root instanceof Element)) return fallback;
    const value = (root.getAttribute("data-bp-template-preview-" + name) || "").trim();
    return value.length > 0 ? value : fallback;
  }

  function bindTemplatePreviewDescriptor(root) {
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

  function bindTemplatePreviewDescriptors(root) {
    const scope = root instanceof Element || root instanceof Document ? root : document;
    const selector = "[data-bp-template-preview-root]";
    const controllers = [];
    if (scope instanceof Element && scope.matches(selector)) {
      const controller = bindTemplatePreviewDescriptor(scope);
      if (controller) controllers.push(controller);
    }
    scope.querySelectorAll(selector).forEach(function (rootNode) {
      const controller = bindTemplatePreviewDescriptor(rootNode);
      if (controller) controllers.push(controller);
    });
    return controllers;
  }

  // API assembly and readiness synchronization.

  const previewDataApi = {
    dataUrl: blueprintDataUrl,
    manifestUrl: blueprintManifestUrl,
    htmlCacheUrl: blueprintHtmlCacheUrl,
    loadManifest: loadBlueprintManifest,
    readManifestStatus: readBlueprintManifestStatus,
    loadManifestEntry: loadBlueprintManifestEntry,
    loadHtmlCache: loadBlueprintHtmlCache,
    readHtmlCacheStatus: readBlueprintHtmlCacheStatus,
    loadHtmlCacheEntry: loadBlueprintHtmlCacheEntry,
    getGraphData: collectGraphData,
    getGraphVariants: collectGraphVariants,
    graphsFromManifest: graphDataFromManifest,
    loadManifestGraphs: loadManifestGraphs,
    loadGraphs: loadBlueprintGraphs,
    graphApiModuleUrl: graphApiModuleUrl,
    previewApiModuleUrl: previewApiModuleUrl,
    previewKey: previewKey,
    statementPreviewKey: statementPreviewKey,
    resolvePreview: resolveBlueprintPreview,
    resolveCanonicalPreview: resolveCanonicalBlueprintPreview
  };

  const previewRenderApi = {
    renderPreviewInto: renderBlueprintPreviewInto,
    renderCanonicalPreviewInto: renderCanonicalBlueprintPreviewInto,
    hydrate: hydrateRenderedPreview
  };

  const previewTemplateHelpers = {
    collectPreviewTemplates: collectPreviewTemplates
  };

  const previewContentHelpers = {
    escapeHtml: escapeHtml,
    previewMessageHtml: previewMessageHtml,
    createPreviewPanel: createPreviewPanel,
    createPreviewSurface: createPreviewSurface
  };

  const previewLifecycleHelpers = {
    bindAnchoredPopover: bindAnchoredPopover,
    hidePreviewSurfaces: hidePreviewSurfaces,
  };

  const previewHydrationHelpers = {
    registerPreviewHydrator: registerPreviewHydrator,
    previewDebug: previewDebug,
    previewDebugLabel: previewDebugLabel
  };

  const stableCustomClientApi = {
    dataUrl: previewDataApi.dataUrl,
    manifestUrl: previewDataApi.manifestUrl,
    htmlCacheUrl: previewDataApi.htmlCacheUrl,
    loadManifest: previewDataApi.loadManifest,
    readManifestStatus: previewDataApi.readManifestStatus,
    loadManifestEntry: previewDataApi.loadManifestEntry,
    loadHtmlCache: previewDataApi.loadHtmlCache,
    readHtmlCacheStatus: previewDataApi.readHtmlCacheStatus,
    loadHtmlCacheEntry: previewDataApi.loadHtmlCacheEntry,
    getGraphData: previewDataApi.getGraphData,
    getGraphVariants: previewDataApi.getGraphVariants,
    graphsFromManifest: previewDataApi.graphsFromManifest,
    loadManifestGraphs: previewDataApi.loadManifestGraphs,
    loadGraphs: previewDataApi.loadGraphs,
    graphApiModuleUrl: previewDataApi.graphApiModuleUrl,
    previewApiModuleUrl: previewDataApi.previewApiModuleUrl,
    previewKey: previewDataApi.previewKey,
    statementPreviewKey: previewDataApi.statementPreviewKey,
    resolvePreview: previewDataApi.resolvePreview,
    renderPreviewInto: previewRenderApi.renderPreviewInto,
    resolveCanonicalPreview: previewDataApi.resolveCanonicalPreview,
    renderCanonicalPreviewInto: previewRenderApi.renderCanonicalPreviewInto,
    hydrate: previewRenderApi.hydrate
  };

  const bundledFeatureRenderHelpers = {
    collectPreviewTemplates: previewTemplateHelpers.collectPreviewTemplates,
    escapeHtml: previewContentHelpers.escapeHtml,
    createPreviewSurface: previewContentHelpers.createPreviewSurface,
    registerPreviewHydrator: previewHydrationHelpers.registerPreviewHydrator,
    previewDebug: previewHydrationHelpers.previewDebug,
    previewDebugLabel: previewHydrationHelpers.previewDebugLabel,
    previewMessageHtml: previewContentHelpers.previewMessageHtml,
    createPreviewPanel: previewContentHelpers.createPreviewPanel,
    bindAnchoredPopover: previewLifecycleHelpers.bindAnchoredPopover,
    hidePreviewSurfaces: previewLifecycleHelpers.hidePreviewSurfaces
  };

  const renderApi = Object.assign(
    {},
    stableCustomClientApi,
    bundledFeatureRenderHelpers
  );

  if (!window.bpGraphApi || typeof window.bpGraphApi !== "object") {
    window.bpGraphApi = {};
  }
  if (typeof window.bpGraphApi.graphApiModuleUrl !== "function") {
    window.bpGraphApi.graphApiModuleUrl = previewDataApi.graphApiModuleUrl;
  }

  function reportRenderReadyError(err) {
    window.setTimeout(function () {
      throw err;
    }, 0);
  }

  function onRenderReady(fn) {
    if (typeof fn !== "function") return;
    fn(renderApi);
  }

  const namespace =
    window.VersoBlueprint && typeof window.VersoBlueprint === "object"
      ? window.VersoBlueprint
      : {};
  const queuedRenderReadyCallbacks = Array.isArray(namespace.renderReadyCallbacks)
    ? namespace.renderReadyCallbacks.slice()
    : [];
  namespace.render = renderApi;
  namespace.onRenderReady = onRenderReady;
  namespace.renderReadyCallbacks = [];
  window.VersoBlueprint = namespace;
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      bindTemplatePreviewDescriptors(document);
    }, { once: true });
  } else {
    bindTemplatePreviewDescriptors(document);
  }
  queuedRenderReadyCallbacks.forEach(function (fn) {
    try {
      onRenderReady(fn);
    } catch (err) {
      reportRenderReadyError(err);
    }
  });
})();
