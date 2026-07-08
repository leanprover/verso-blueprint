import { escapeHtml, readHtml } from "./preview-runtime-base.mjs";
import { missingPreviewKeyDiagnosticHtml, previewKey } from "./preview-runtime-data.mjs";
import { hydrateRenderedPreview } from "./preview-runtime-hydration.mjs";

  // Preview resolution joins semantic manifest entries with opaque body fragments.
  //
  // The HTML cache is presentation data. Runtime code may insert and hydrate
  // its fragments, but semantic facts must come from the manifest entry. If a
  // future client needs another fact, add it to the manifest instead of parsing
  // cached HTML.

  function errorMessage(err) {
    return err instanceof Error && typeof err.message === "string" && err.message.length > 0
      ? err.message
      : String(err);
  }

  function blueprintDataApi(options) {
    const opts = options && typeof options === "object" ? options : {};
    return opts.dataApi && typeof opts.dataApi === "object" ? opts.dataApi : null;
  }

  function requireBlueprintDataApi(options) {
    const dataApi = blueprintDataApi(options);
    if (!dataApi) {
      throw new Error("Blueprint data API missing; call through createPreview() or createBlueprintDataApi()");
    }
    return dataApi;
  }

  function loadManifestEntry(previewKey, options) {
    const dataApi = requireBlueprintDataApi(options);
    return dataApi.loadManifestEntry(previewKey, options);
  }

  function loadHtmlCacheEntry(previewKey, options) {
    const dataApi = requireBlueprintDataApi(options);
    return dataApi.loadHtmlCacheEntry(previewKey, options);
  }

  function manifestDiagnosticHtml(previewKey, options) {
    return requireBlueprintDataApi(options).manifestDiagnosticHtml(previewKey);
  }

  function htmlCacheDiagnosticHtml(previewKey, options) {
    return requireBlueprintDataApi(options).htmlCacheDiagnosticHtml(previewKey);
  }

  function htmlCacheReady(options) {
    const dataApi = requireBlueprintDataApi(options);
    if (typeof dataApi.readHtmlCacheStatus !== "function") return false;
    const status = dataApi.readHtmlCacheStatus();
    return !!(status && status.state === "ready");
  }

  function semanticOnlyPreviewBodyMissing(entry, options) {
    return !!(
      entry &&
      typeof entry === "object" &&
      entry.targetKind === "externalMarkup" &&
      htmlCacheReady(options)
    );
  }

  function semanticOnlyPreviewDiagnosticHtml(previewKey) {
    const key = typeof previewKey === "string" ? previewKey.trim() : "";
    const keyHtml = key ? "<p>Requested preview: <code>" + escapeHtml(key) + "</code></p>" : "";
    return (
      "<div class=\"bp_html_cache_preview_notice\">" +
      "<p><strong>Preview body unavailable.</strong></p>" +
      "<p>This Blueprint entry is present in the manifest, but this generated artifact set " +
      "does not include a rendered preview body for it.</p>" +
      keyHtml +
      "</div>"
    );
  }

  export async function resolveBlueprintPreview(previewKey, options) {
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
      loadManifestEntry(key, options),
      loadHtmlCacheEntry(key, options)
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
        diagnosticHtml: manifestDiagnosticHtml(key, options)
      };
    }
    if (!html) {
      if (semanticOnlyPreviewBodyMissing(manifestEntry, options)) {
        return {
          ok: false,
          key: key,
          reason: "semantic-preview-body-missing",
          manifestEntry: manifestEntry,
          htmlCacheEntry: htmlCacheEntry,
          html: "",
          diagnosticHtml: semanticOnlyPreviewDiagnosticHtml(key)
        };
      }
      return {
        ok: false,
        key: key,
        reason: "html-cache-entry-missing",
        manifestEntry: manifestEntry,
        htmlCacheEntry: htmlCacheEntry,
        html: "",
        diagnosticHtml: htmlCacheDiagnosticHtml(key, options)
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

  // Rendered-fragment insertion.

  export function renderHtmlInto(target, html, options) {
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

  export async function renderBlueprintPreviewInto(target, previewKey, options) {
    if (!(target instanceof Element)) {
      throw new Error("renderBlueprintPreviewInto target must be a DOM Element");
    }
    const opts = options && typeof options === "object" ? options : {};
    const result = await resolveBlueprintPreview(previewKey, opts);
    const html = result.ok ? result.html : (opts.diagnostics === false ? "" : result.diagnosticHtml);
    renderHtmlInto(target, html, opts);
    return result;
  }

  // Label-oriented node rendering.
  //
  // `renderPreviewInto` renders an exact manifest/cache key. `renderNode`
  // starts from a Blueprint label, tries the native rendered preview first, and
  // can fall back to call-scoped external-markup renderers for labels whose
  // only portable body is TeX or Markdown source.

  export function renderNodeDiagnosticHtml(title, detail, fields) {
    const data = fields && typeof fields === "object" ? fields : {};
    const parts = [
      "<p><strong>" + escapeHtml(title) + "</strong></p>",
      "<p>" + escapeHtml(detail) + "</p>"
    ];
    if (data.label) {
      parts.push("<p>Requested label: <code>" + escapeHtml(data.label) + "</code></p>");
    }
    if (data.key) {
      parts.push("<p>Requested preview: <code>" + escapeHtml(data.key) + "</code></p>");
    }
    if (data.language || data.slot) {
      const language = data.language || "any";
      const slot = data.slot || "any";
      parts.push(
        "<p>Requested external markup: <code>" +
          escapeHtml(language) +
          "</code> / <code>" +
          escapeHtml(slot) +
          "</code></p>"
      );
    }
    return "<div class=\"bp_html_cache_preview_notice\">" + parts.join("") + "</div>";
  }

  export function normalizeRenderNodeRequest(request) {
    if (typeof request === "string") {
      return {
        label: request.trim(),
        facet: "statement",
        externalMarkup: null
      };
    }
    const opts = request && typeof request === "object" ? request : {};
    const label = typeof opts.label === "string" ? opts.label.trim() : "";
    const facet =
      typeof opts.facet === "string" && opts.facet.trim()
        ? opts.facet.trim()
        : "statement";
    const externalMarkup =
      opts.externalMarkup && typeof opts.externalMarkup === "object"
        ? opts.externalMarkup
        : (opts.preferredExternalMarkup && typeof opts.preferredExternalMarkup === "object"
            ? opts.preferredExternalMarkup
            : null);
    return {
      label,
      facet,
      externalMarkup
    };
  }

  export function renderNodePreviewResult(result, fields) {
    return Object.assign(
      {},
      {
        renderMode: "",
        label: "",
        facet: "",
        externalMarkup: null,
        nativePreview: null
      },
      result || {},
      fields || {}
    );
  }

  export function externalMarkupEntryKey(label) {
    const trimmedLabel = typeof label === "string" ? label.trim() : "";
    return trimmedLabel ? "externalMarkup:" + trimmedLabel : "";
  }

  export async function loadExternalMarkupNodeEntry(label, options) {
    const key = externalMarkupEntryKey(label);
    if (!key) return null;
    return loadManifestEntry(key, options);
  }

  export function normalizeExternalMarkupPreferences(externalMarkup) {
    if (!externalMarkup || typeof externalMarkup !== "object") return [];
    if (Array.isArray(externalMarkup)) return externalMarkup;
    if (Array.isArray(externalMarkup.prefer)) return externalMarkup.prefer;
    return [externalMarkup];
  }

  export function normalizeExternalMarkupToken(value) {
    return typeof value === "string" ? value.trim().toLowerCase() : "";
  }

  export function isNativeMarkupPreference(preference) {
    if (!preference || typeof preference !== "object") return false;
    const language = normalizeExternalMarkupToken(preference.language);
    return language === "verso" || language === "native";
  }

  export function externalMarkupPreferenceDisplay(preference) {
    return normalizeExternalMarkupToken(preference && preference.display);
  }

  export function externalMarkupPreferenceCanRender(preference) {
    return (
      preference &&
      typeof preference === "object" &&
      (typeof preference.render === "function" ||
        externalMarkupPreferenceDisplay(preference) === "source")
    );
  }

  export function externalMarkupMatchesPreference(markup, preference) {
    if (!markup || typeof markup !== "object") return false;
    const language = normalizeExternalMarkupToken(preference && preference.language);
    const slot =
      preference && typeof preference.slot === "string" ? preference.slot.trim() : "";
    if (language && normalizeExternalMarkupToken(markup.language) !== language) return false;
    if (slot && String(markup.slot || "").trim() !== slot) return false;
    return typeof markup.raw === "string" && markup.raw.length > 0;
  }

  export function firstExternalMarkupForPreference(entry, preference) {
    const markups =
      entry && Array.isArray(entry.externalMarkup) ? entry.externalMarkup : [];
    return markups.find(function (markup) {
      return externalMarkupMatchesPreference(markup, preference);
    }) || null;
  }

  export function selectExternalMarkup(entry, preferences) {
    let missingRenderer = null;
    let missingMarkupPreference = null;
    for (const preference of preferences) {
      if (!preference || typeof preference !== "object") continue;
      if (isNativeMarkupPreference(preference)) continue;
      const markup = firstExternalMarkupForPreference(entry, preference);
      if (!markup) {
        if (!missingMarkupPreference) missingMarkupPreference = preference;
        continue;
      }
      if (externalMarkupPreferenceCanRender(preference)) {
        return {
          ok: true,
          markup,
          preference
        };
      }
      if (!missingRenderer) {
        missingRenderer = {
          ok: false,
          reason: "external-markup-renderer-missing",
          markup,
          preference
        };
      }
    }
    return missingRenderer || {
      ok: false,
      reason: "external-markup-missing",
      markup: null,
      preference: missingMarkupPreference
    };
  }

  export function renderExternalMarkupSource(target, markup) {
    const pre = document.createElement("pre");
    pre.className = "bp_external_markup_source";
    const code = document.createElement("code");
    code.textContent = markup && typeof markup.raw === "string" ? markup.raw : "";
    pre.appendChild(code);
    target.replaceChildren(pre);
  }

  export async function renderExternalMarkupSelectionInto(target, selection, payload) {
    const preference = selection.preference || {};
    if (externalMarkupPreferenceDisplay(preference) === "source") {
      renderExternalMarkupSource(target, selection.markup);
      return;
    }
    const renderer = preference.render;
    if (typeof renderer !== "function") {
      throw new Error("External markup renderer missing");
    }
    target.replaceChildren();
    const rendered = await renderer(payload, target);
    if (rendered instanceof Node) {
      target.replaceChildren(rendered);
    } else if (typeof rendered === "string") {
      target.innerHTML = rendered;
    }
  }

  export async function callExternalMarkupRenderer(target, selection, payload, options) {
    await renderExternalMarkupSelectionInto(target, selection, payload);
    hydrateRenderedPreview(target, options);
  }

  export function externalMarkupRendererPayload(request, manifestEntry, selection, nativeResult) {
    const markup = selection.markup || {};
    return {
      raw: typeof markup.raw === "string" ? markup.raw : "",
      language: typeof markup.language === "string" ? markup.language : "",
      slot: typeof markup.slot === "string" ? markup.slot : "",
      location: markup.location || null,
      node: manifestEntry || null,
      manifestEntry: manifestEntry || null,
      label: request.label,
      facet: request.facet,
      nativePreview: nativeResult || null,
      externalMarkup: markup
    };
  }

  export function blueprintContentTargetForNode(node) {
    if (!(node instanceof Element)) return null;
    const direct = Array.from(node.children).find(function (child) {
      return child instanceof Element && child.classList.contains("bp_content");
    });
    if (direct instanceof Element) return direct;
    return node.querySelector(".bp_content");
  }

  export async function loadCanonicalPreviewNode(entry, result, options) {
    const url = canonicalPreviewUrl(entry, options);
    if (!url) {
      return {
        ok: false,
        reason: "canonical-href-missing",
        detail: "The manifest entry did not include a generated-page link for this preview.",
        node: null,
        canonicalHtml: "",
        canonicalSourceHref: ""
      };
    }
    try {
      const doc = await loadCanonicalPreviewDocument(url, options);
      const id = canonicalPreviewId(url, result);
      const node = id ? doc.getElementById(id) : null;
      if (!(node instanceof Element)) {
        return {
          ok: false,
          reason: "canonical-preview-node-missing",
          detail: "The generated page loaded, but the linked Blueprint node was not present.",
          node: null,
          canonicalHtml: "",
          canonicalSourceHref: url.href
        };
      }
      const clone = node.cloneNode(true);
      if (!(clone instanceof Element)) {
        return {
          ok: false,
          reason: "canonical-preview-node-missing",
          detail: "The generated page loaded, but the linked Blueprint node clone was not an element.",
          node: null,
          canonicalHtml: "",
          canonicalSourceHref: url.href
        };
      }
      rebaseCanonicalPreviewLinks(clone, canonicalPreviewDocumentBaseUrl(doc, url));
      resetClonedPreviewBindingState(clone);
      return {
        ok: true,
        reason: "",
        detail: "",
        node: clone,
        canonicalHtml: clone.outerHTML,
        canonicalSourceHref: url.href
      };
    } catch (err) {
      const message = errorMessage(err);
      return {
        ok: false,
        reason: "canonical-preview-load-failed",
        detail: message,
        node: null,
        canonicalHtml: "",
        canonicalSourceHref: url.href
      };
    }
  }

  export async function renderExternalMarkupNodeInto(target, result, selection, payload, options) {
    const loaded = await loadCanonicalPreviewNode(result.manifestEntry, result, options);
    if (!loaded.ok) {
      return {
        ok: false,
        reason: loaded.reason === "canonical-preview-load-failed"
          ? "external-markup-node-shell-load-failed"
          : "external-markup-node-shell-missing",
        detail: loaded.detail,
        node: null,
        canonicalHtml: "",
        canonicalSourceHref: loaded.canonicalSourceHref
      };
    }
    const loadedNode = loaded.node;
    if (!(loadedNode instanceof Element)) {
      return {
        ok: false,
        reason: "external-markup-node-shell-missing",
        detail: "The generated Blueprint node shell was not an element.",
        node: null,
        canonicalHtml: "",
        canonicalSourceHref: loaded.canonicalSourceHref
      };
    }
    const contentTarget = blueprintContentTargetForNode(loadedNode);
    if (!(contentTarget instanceof Element)) {
      return {
        ok: false,
        reason: "external-markup-node-shell-missing",
        detail: "The generated Blueprint node shell did not include a content slot.",
        node: null,
        canonicalHtml: "",
        canonicalSourceHref: loaded.canonicalSourceHref
      };
    }
    await renderExternalMarkupSelectionInto(contentTarget, selection, payload);
    target.replaceChildren(loadedNode);
    hydrateRenderedPreview(target, options);
    return {
      ok: true,
      reason: "",
      detail: "",
      node: loadedNode,
      canonicalHtml: loadedNode.outerHTML,
      canonicalSourceHref: loaded.canonicalSourceHref
    };
  }

  export async function renderBlueprintNodeInto(target, request, options) {
    if (!(target instanceof Element)) {
      throw new Error("renderBlueprintNodeInto target must be a DOM Element");
    }
    const opts = options && typeof options === "object" ? options : {};
    const normalized = normalizeRenderNodeRequest(request);
    if (!normalized.label) {
      const result = renderNodePreviewResult({
        ok: false,
        key: "",
        reason: "missing-label",
        manifestEntry: null,
        htmlCacheEntry: null,
        html: "",
        diagnosticHtml: renderNodeDiagnosticHtml(
          "Blueprint label missing.",
          "Provide a Blueprint node label to render.",
          {}
        )
      }, normalized);
      if (opts.diagnostics !== false) renderHtmlInto(target, result.diagnosticHtml, opts);
      else target.replaceChildren();
      return result;
    }

    const nativeKey = previewKey(normalized.label, normalized.facet);
    const nativeResult = await resolveBlueprintPreview(nativeKey, opts);
    if (nativeResult.ok) {
      const canonicalResult = await resolveCanonicalBlueprintPreview(nativeKey, opts);
      const result = renderNodePreviewResult(canonicalResult, {
        renderMode: canonicalResult.ok ? "native" : "diagnostic",
        label: normalized.label,
        facet: normalized.facet,
        nativePreview: nativeResult
      });
      const html = result.ok
        ? result.canonicalHtml
        : (opts.diagnostics === false ? "" : result.diagnosticHtml);
      renderHtmlInto(target, html, opts);
      return result;
    }

    const preferences = normalizeExternalMarkupPreferences(normalized.externalMarkup);
    if (preferences.length === 0) {
      const result = renderNodePreviewResult(nativeResult, {
        renderMode: "diagnostic",
        label: normalized.label,
        facet: normalized.facet,
        nativePreview: nativeResult
      });
      const html = opts.diagnostics === false ? "" : result.diagnosticHtml;
      renderHtmlInto(target, html, opts);
      return result;
    }

    const manifestEntry =
      nativeResult.manifestEntry || (await loadExternalMarkupNodeEntry(normalized.label, opts));
    if (!manifestEntry) {
      const result = renderNodePreviewResult({
        ok: false,
        key: nativeKey,
        reason: "external-markup-entry-missing",
        manifestEntry: null,
        htmlCacheEntry: nativeResult.htmlCacheEntry || null,
        html: "",
        diagnosticHtml: renderNodeDiagnosticHtml(
          "External markup entry missing.",
          "The manifest has no native preview or external-markup entry for this label.",
          { label: normalized.label, key: nativeKey }
        )
      }, {
        renderMode: "diagnostic",
        label: normalized.label,
        facet: normalized.facet,
        nativePreview: nativeResult
      });
      const html = opts.diagnostics === false ? "" : result.diagnosticHtml;
      renderHtmlInto(target, html, opts);
      return result;
    }

    const selection = selectExternalMarkup(manifestEntry, preferences);
    if (!selection.ok) {
      const preference = selection.preference || {};
      const result = renderNodePreviewResult({
        ok: false,
        key: manifestEntry.key || nativeKey,
        reason: selection.reason,
        manifestEntry,
        htmlCacheEntry: nativeResult.htmlCacheEntry || null,
        html: "",
        diagnosticHtml: renderNodeDiagnosticHtml(
          selection.reason === "external-markup-renderer-missing"
            ? "External markup renderer missing."
            : "External markup missing.",
          selection.reason === "external-markup-renderer-missing"
            ? "The requested external markup exists, but this render call did not provide a renderer or source display fallback."
            : "The manifest entry did not include external markup matching this render call.",
          {
            label: normalized.label,
            key: manifestEntry.key || nativeKey,
            language: preference.language,
            slot: preference.slot
          }
        )
      }, {
        renderMode: "diagnostic",
        label: normalized.label,
        facet: normalized.facet,
        externalMarkup: selection.markup || null,
        nativePreview: nativeResult
      });
      const html = opts.diagnostics === false ? "" : result.diagnosticHtml;
      renderHtmlInto(target, html, opts);
      return result;
    }

    const result = renderNodePreviewResult({
      ok: true,
      key: manifestEntry.key || nativeKey,
      reason: "",
      manifestEntry,
      htmlCacheEntry: nativeResult.htmlCacheEntry || null,
      html: "",
      diagnosticHtml: ""
    }, {
      renderMode: "external-markup",
      label: normalized.label,
      facet: normalized.facet,
      externalMarkup: selection.markup,
      nativePreview: nativeResult
    });
    const payload = externalMarkupRendererPayload(normalized, manifestEntry, selection, nativeResult);
    try {
      const rendered = await renderExternalMarkupNodeInto(target, result, selection, payload, opts);
      if (rendered.ok) {
        return renderNodePreviewResult(result, {
          canonicalHtml: rendered.canonicalHtml,
          canonicalSourceHref: rendered.canonicalSourceHref
        });
      }
      const failed = renderNodePreviewResult(result, {
        ok: false,
        reason: rendered.reason,
        diagnosticHtml: renderNodeDiagnosticHtml(
          rendered.reason === "external-markup-node-shell-load-failed"
            ? "External markup node shell unavailable."
            : "External markup node shell missing.",
          rendered.detail,
          {
            label: normalized.label,
            key: result.key,
            language: selection.markup.language,
            slot: selection.markup.slot
          }
        ),
        canonicalSourceHref: rendered.canonicalSourceHref || ""
      });
      const html = opts.diagnostics === false ? "" : failed.diagnosticHtml;
      renderHtmlInto(target, html, opts);
      return failed;
    } catch (err) {
      const message = errorMessage(err);
      const failed = renderNodePreviewResult(result, {
        ok: false,
        reason: "external-markup-render-failed",
        diagnosticHtml: renderNodeDiagnosticHtml(
          "External markup renderer failed.",
          message,
          {
            label: normalized.label,
            key: result.key,
            language: selection.markup.language,
            slot: selection.markup.slot
          }
        )
      });
      const html = opts.diagnostics === false ? "" : failed.diagnosticHtml;
      renderHtmlInto(target, html, opts);
      return failed;
    }
  }

  export const canonicalPreviewDocuments = new Map();
  export const canonicalPreviewHtmlByKey = new Map();

  // Canonical generated-node rendering.
  //
  // The HTML cache intentionally carries reusable body fragments, not full
  // Blueprint node wrappers. To render the exact Lean-generated shell without
  // duplicating wrapper semantics in JavaScript or emitting a second wrapper
  // cache, follow the manifest href, clone the canonical node, and rebase its
  // links for insertion into the current page.

  export function urlWithoutHash(url) {
    const clone = new URL(url.href);
    clone.hash = "";
    return clone.href;
  }

  export function canonicalPreviewDocumentCache(options) {
    const opts = options && typeof options === "object" ? options : {};
    return opts.canonicalPreviewDocuments instanceof Map
      ? opts.canonicalPreviewDocuments
      : canonicalPreviewDocuments;
  }

  export function canonicalPreviewHtmlCache(options) {
    const opts = options && typeof options === "object" ? options : {};
    return opts.canonicalPreviewHtmlByKey instanceof Map
      ? opts.canonicalPreviewHtmlByKey
      : canonicalPreviewHtmlByKey;
  }

  export function canonicalPreviewBaseUrl(options) {
    const opts = options && typeof options === "object" ? options : {};
    if (typeof opts.canonicalBaseUrl === "string" && opts.canonicalBaseUrl.trim()) {
      return opts.canonicalBaseUrl.trim();
    }
    if (typeof document !== "undefined" && document.baseURI) return document.baseURI;
    if (typeof window !== "undefined" && window.location) return window.location.href;
    return "";
  }

  export function canonicalPreviewUrl(entry, options) {
    if (!entry || typeof entry !== "object" || typeof entry.href !== "string") return null;
    const href = entry.href.trim();
    if (!href) return null;
    try {
      const baseUrl = canonicalPreviewBaseUrl(options);
      return baseUrl ? new URL(href, baseUrl) : new URL(href);
    } catch (_err) {
      return null;
    }
  }

  export function canonicalPreviewId(url, result) {
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

  export function canonicalPreviewDiagnosticHtml(title, detail, previewKey) {
    const keyHtml = previewKey ? "<p>Requested preview: <code>" + escapeHtml(previewKey) + "</code></p>" : "";
    return (
      "<div class=\"bp_html_cache_preview_notice\">" +
      "<p><strong>" + escapeHtml(title) + "</strong></p>" +
      "<p>" + escapeHtml(detail) + "</p>" +
      keyHtml +
      "</div>"
    );
  }

  export function canonicalPreviewResult(result, fields) {
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

  export function parseCanonicalPreviewHtml(html) {
    if (typeof DOMParser === "undefined") {
      throw new Error("Canonical preview loading requires DOMParser or options.loadDocument");
    }
    return new DOMParser().parseFromString(String(html || ""), "text/html");
  }

  function defaultCanonicalPreviewFetchText(pageUrl, options) {
    const opts = options && typeof options === "object" ? options : {};
    if (typeof opts.fetchText === "function") {
      return Promise.resolve(opts.fetchText(pageUrl, opts));
    }
    const globalScope = typeof globalThis !== "undefined" ? globalThis : {};
    const fetchFn = globalScope && globalScope.fetch;
    if (typeof fetchFn !== "function") {
      return Promise.reject(
        new Error("Canonical preview loading requires fetch, options.fetchText, or options.loadDocument")
      );
    }
    const fetchOptions =
      opts.fetchOptions && typeof opts.fetchOptions === "object"
        ? opts.fetchOptions
        : undefined;
    return fetchFn.call(globalScope, pageUrl, fetchOptions).then(function (resp) {
      if (!resp.ok) {
        throw new Error("HTTP " + resp.status + " while loading " + pageUrl);
      }
      return resp.text();
    });
  }

  function normalizeCanonicalPreviewDocument(loaded) {
    if (typeof loaded === "string") return parseCanonicalPreviewHtml(loaded);
    if (loaded && typeof loaded.getElementById === "function") return loaded;
    throw new Error("Canonical preview loader did not return a Document");
  }

  export async function loadCanonicalPreviewDocument(url, options) {
    const pageUrl = urlWithoutHash(url);
    const cache = canonicalPreviewDocumentCache(options);
    const existing = cache.get(pageUrl);
    if (existing) return existing;
    // Do not shortcut same-page URLs to `document`: hydration mutates the live
    // DOM by moving local panels to body and adding binding state.
    const opts = options && typeof options === "object" ? options : {};
    const promise =
      typeof opts.loadDocument === "function"
        ? Promise.resolve(opts.loadDocument({ url: pageUrl, sourceUrl: url.href, options: opts }))
            .then(normalizeCanonicalPreviewDocument)
        : defaultCanonicalPreviewFetchText(pageUrl, opts)
            .then(parseCanonicalPreviewHtml);
    cache.set(pageUrl, promise);
    return promise;
  }

  export function rebaseUrlAttribute(node, attrName, baseUrl) {
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

  export function forEachMatchingElement(root, selector, callback) {
    if (!(root instanceof Element)) return;
    if (root.matches(selector)) callback(root);
    root.querySelectorAll(selector).forEach(function (node) {
      callback(node);
    });
  }

  export function canonicalPreviewDocumentBaseUrl(doc, sourceUrl) {
    const pageUrl = urlWithoutHash(sourceUrl);
    const base =
      doc && typeof doc.querySelector === "function"
        ? doc.querySelector("base[href]")
        : null;
    const href = base instanceof Element ? (base.getAttribute("href") || "").trim() : "";
    if (href.length > 0) {
      try {
        return new URL(href, pageUrl).href;
      } catch (_err) {}
    }
    return pageUrl;
  }

  export function rebaseCanonicalPreviewLinks(root, baseUrl) {
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

  export const clonedPreviewBindingStateAttributes = Object.freeze([
    "data-bp-bound",
    "data-bp-dismiss-bound",
    "data-bp-popover-bound",
    "data-bp-panel-reposition-bound",
    "data-bp-preview-trigger-bound",
    "data-bp-preview-events-bound",
    "data-bp-preview-panel-lifetime-bound",
    "data-bp-template-preview-bound",
    "data-bp-inline-main-bound",
    "data-bp-inline-child-bound",
    "data-bp-inline-panel-reposition-bound",
    "data-bp-relation-chip-bound",
    "data-bp-relation-panel-lifetime-bound",
    "data-bp-relation-dismiss-bound",
    "data-bp-preview-bound",
    "data-bp-variant-bound",
    "data-bp-legend-bound",
    "data-bp-options-bound",
    "data-bp-group-hover-bound",
    "data-bp-graph-panel-dismiss-bound",
    "data-bp-graph-panel-reposition-bound"
  ]);

  export function resetClonedPreviewBindingState(root) {
    if (!(root instanceof Element)) return;
    const selector = clonedPreviewBindingStateAttributes.map(function (attr) {
      return "[" + attr + "]";
    }).join(",");
    const reset = function (node) {
      clonedPreviewBindingStateAttributes.forEach(function (attr) {
        node.removeAttribute(attr);
      });
    };
    reset(root);
    root.querySelectorAll(selector).forEach(reset);
  }

  export async function resolveCanonicalBlueprintPreview(previewKey, options) {
    const opts = options && typeof options === "object" ? options : {};
    const result = await resolveBlueprintPreview(previewKey, opts);
    if (!result.ok) {
      return canonicalPreviewResult(result);
    }
    const cache = canonicalPreviewHtmlCache(opts);
    const cached = cache.get(result.key);
    if (cached) {
      return canonicalPreviewResult(result, {
        canonicalHtml: cached.html,
        canonicalSourceHref: cached.href
      });
    }
    const loaded = await loadCanonicalPreviewNode(result.manifestEntry, result, opts);
    if (!loaded.ok) {
      const title =
        loaded.reason === "canonical-href-missing"
          ? "Canonical preview link missing."
          : loaded.reason === "canonical-preview-node-missing"
            ? "Canonical preview node missing."
            : "Canonical preview page unavailable.";
      return canonicalPreviewResult(result, {
        ok: false,
        reason: loaded.reason,
        canonicalSourceHref: loaded.canonicalSourceHref,
        diagnosticHtml: canonicalPreviewDiagnosticHtml(
          title,
          loaded.detail,
          result.key
        )
      });
    }
    const canonical = {
      html: loaded.canonicalHtml,
      href: loaded.canonicalSourceHref
    };
    cache.set(result.key, canonical);
    return canonicalPreviewResult(result, {
      canonicalHtml: canonical.html,
      canonicalSourceHref: canonical.href
    });
  }

  export async function renderCanonicalBlueprintPreviewInto(target, previewKey, options) {
    if (!(target instanceof Element)) {
      throw new Error("renderCanonicalBlueprintPreviewInto target must be a DOM Element");
    }
    const opts = options && typeof options === "object" ? options : {};
    const result = await resolveCanonicalBlueprintPreview(previewKey, opts);
    const html = result.ok
      ? result.canonicalHtml
      : (opts.diagnostics === false ? "" : result.diagnosticHtml);
    renderHtmlInto(target, html, opts);
    return result;
  }

  export const previewRuntimeRender = {
    resolveBlueprintPreview,
    renderHtmlInto,
    renderBlueprintPreviewInto,
    renderNodeDiagnosticHtml,
    normalizeRenderNodeRequest,
    renderNodePreviewResult,
    externalMarkupEntryKey,
    loadExternalMarkupNodeEntry,
    normalizeExternalMarkupPreferences,
    normalizeExternalMarkupToken,
    isNativeMarkupPreference,
    externalMarkupPreferenceDisplay,
    externalMarkupPreferenceCanRender,
    externalMarkupMatchesPreference,
    firstExternalMarkupForPreference,
    selectExternalMarkup,
    renderExternalMarkupSource,
    renderExternalMarkupSelectionInto,
    callExternalMarkupRenderer,
    externalMarkupRendererPayload,
    blueprintContentTargetForNode,
    loadCanonicalPreviewNode,
    renderExternalMarkupNodeInto,
    renderBlueprintNodeInto,
    canonicalPreviewDocuments,
    canonicalPreviewHtmlByKey,
    urlWithoutHash,
    canonicalPreviewDocumentCache,
    canonicalPreviewHtmlCache,
    canonicalPreviewBaseUrl,
    canonicalPreviewUrl,
    canonicalPreviewId,
    canonicalPreviewDiagnosticHtml,
    canonicalPreviewResult,
    parseCanonicalPreviewHtml,
    loadCanonicalPreviewDocument,
    rebaseUrlAttribute,
    forEachMatchingElement,
    canonicalPreviewDocumentBaseUrl,
    rebaseCanonicalPreviewLinks,
    clonedPreviewBindingStateAttributes,
    resetClonedPreviewBindingState,
    resolveCanonicalBlueprintPreview,
    renderCanonicalBlueprintPreviewInto
  };

export default previewRuntimeRender;
