import { dataApiModuleUrl as coreDataApiModuleUrl, dataUrl as coreDataUrl, graphApiModuleUrl as coreGraphApiModuleUrl, htmlCacheUrl as coreHtmlCacheUrl, manifestUrl as coreManifestUrl, previewApiModuleUrl as corePreviewApiModuleUrl, previewKey as corePreviewKey, statementPreviewKey as coreStatementPreviewKey } from "../blueprint-preview-core.mjs";
import { escapeHtml, previewDebug } from "./preview-runtime-base.mjs";

  // Generated-data URL helpers.

  function normalizeBlueprintDataOptions(options) {
    return options && typeof options === "object" ? options : {};
  }

  function readOptionString(options, name) {
    const opts = normalizeBlueprintDataOptions(options);
    return typeof opts[name] === "string" ? opts[name] : "";
  }

  function readOptionFunction(options, name) {
    const opts = normalizeBlueprintDataOptions(options);
    return typeof opts[name] === "function" ? opts[name] : null;
  }

  function createBlueprintStore(fields) {
    return Object.assign({
      status: null,
      map: null,
      promise: null
    }, fields || {});
  }

  export function createBlueprintDataApi(options) {
    const initialOptions = normalizeBlueprintDataOptions(options);
    let blueprintDataBaseUrl = readOptionString(initialOptions, "dataBaseUrl");
    let blueprintFetchJson = readOptionFunction(initialOptions, "fetchJson");

    function readBlueprintDataBaseUrl() {
      return blueprintDataBaseUrl || undefined;
    }

    function readBlueprintFetchJson() {
      return blueprintFetchJson;
    }

    function setBlueprintDataBaseUrlForApi(baseUrl) {
      const nextBaseUrl = typeof baseUrl === "string" ? baseUrl : "";
      if (blueprintDataBaseUrl === nextBaseUrl) return;
      blueprintDataBaseUrl = nextBaseUrl;
      resetBlueprintDataStoresForApi();
    }

    function setBlueprintFetchJsonForApi(fetchJson) {
      const nextFetchJson = typeof fetchJson === "function" ? fetchJson : null;
      if (blueprintFetchJson === nextFetchJson) return;
      blueprintFetchJson = nextFetchJson;
      resetBlueprintDataStoresForApi();
    }

    function blueprintDataUrlForApi(filename) {
      return coreDataUrl(filename, readBlueprintDataBaseUrl());
    }

    function blueprintDataLoadOptions(options) {
      const opts = normalizeBlueprintDataOptions(options);
      const loadOptions = Object.assign({}, opts);
      if (typeof loadOptions.fetchJson !== "function") {
        const fetchJson = readBlueprintFetchJson();
        if (fetchJson) loadOptions.fetchJson = fetchJson;
      }
      return loadOptions;
    }

    function fetchBlueprintJsonForApi(url, options) {
      const opts = blueprintDataLoadOptions(options);
      if (typeof opts.fetchJson === "function") {
        return Promise.resolve(opts.fetchJson(url, opts));
      }
      const globalScope = typeof globalThis !== "undefined" ? globalThis : {};
      const fetchFn = globalScope && globalScope.fetch;
      if (typeof fetchFn !== "function") {
        return Promise.reject(
          new Error("Blueprint preview API requires fetch or createPreview({ fetchJson })")
        );
      }
      const fetchOptions =
        opts.fetchOptions && typeof opts.fetchOptions === "object"
          ? opts.fetchOptions
          : undefined;
      return fetchFn.call(globalScope, url, fetchOptions).then(function (resp) {
        if (!resp.ok) {
          throw new Error("HTTP " + resp.status + " while loading " + url);
        }
        return resp.json();
      });
    }

    function blueprintManifestUrlForApi() {
      return coreManifestUrl(readBlueprintDataBaseUrl());
    }

    function dataApiModuleUrlForApi() {
      return coreDataApiModuleUrl(readBlueprintDataBaseUrl());
    }

    function previewApiModuleUrlForApi() {
      return corePreviewApiModuleUrl(readBlueprintDataBaseUrl());
    }

    function graphApiModuleUrlForApi() {
      return coreGraphApiModuleUrl(readBlueprintDataBaseUrl());
    }

    function blueprintHtmlCacheUrlForApi() {
      return coreHtmlCacheUrl(readBlueprintDataBaseUrl());
    }

    // Manifest/cache status, loading, and diagnostics.

    const blueprintManifestStoreForApi = createBlueprintStore({
      url: blueprintManifestUrlForApi,
      decode: decodeBlueprintManifest,
      debugLabel: "manifest.loadFailed",
      consoleLabel: "Blueprint manifest",
      unavailableTitle: "Preview manifest unavailable.",
      requiredFilename: "blueprint-manifest.json",
      missingTitle: "Preview entry missing from manifest.",
      missingReadyText: "The site emitted a Blueprint manifest, but this preview key was not present."
    });

    const blueprintHtmlCacheStoreForApi = createBlueprintStore({
      url: blueprintHtmlCacheUrlForApi,
      decode: decodeBlueprintHtmlCache,
      debugLabel: "htmlCache.loadFailed",
      consoleLabel: "Blueprint HTML cache",
      unavailableTitle: "Preview HTML cache unavailable.",
      requiredFilename: "blueprint-html-cache.json",
      missingTitle: "Preview entry missing from HTML cache.",
      missingReadyText: "The site emitted a rendered-fragment cache, but this preview key was not present."
    });

    function resetBlueprintStoreForApi(store) {
      store.status = null;
      store.map = null;
      store.promise = null;
    }

    function resetBlueprintDataStoresForApi() {
      resetBlueprintStoreForApi(blueprintManifestStoreForApi);
      resetBlueprintStoreForApi(blueprintHtmlCacheStoreForApi);
    }

    function defaultBlueprintStoreStatusForApi(store) {
      return {
        state: "idle",
        attempts: 0,
        url: store.url(),
        lastError: "",
        entryCount: 0
      };
    }

    function cloneBlueprintStoreStatusForApi(store, status) {
      const fallback = defaultBlueprintStoreStatusForApi(store);
      if (!status || typeof status !== "object") return fallback;
      return {
        state: typeof status.state === "string" ? status.state : fallback.state,
        attempts: Number.isFinite(status.attempts) ? status.attempts : fallback.attempts,
        url: typeof status.url === "string" ? status.url : fallback.url,
        lastError: typeof status.lastError === "string" ? status.lastError : fallback.lastError,
        entryCount: Number.isFinite(status.entryCount) ? status.entryCount : fallback.entryCount
      };
    }

    function readBlueprintStoreStatusForApi(store) {
      return cloneBlueprintStoreStatusForApi(store, store.status);
    }

    function setBlueprintStoreStatusForApi(store, status) {
      store.status = status;
      return status;
    }

    function readBlueprintManifestStatusForApi() {
      return readBlueprintStoreStatusForApi(blueprintManifestStoreForApi);
    }

    function readBlueprintHtmlCacheStatusForApi() {
      return readBlueprintStoreStatusForApi(blueprintHtmlCacheStoreForApi);
    }

    function blueprintStoreDiagnosticHtmlForApi(store, previewKey) {
      const status = readBlueprintStoreStatusForApi(store);
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

    function blueprintManifestDiagnosticHtmlForApi(previewKey) {
      return blueprintStoreDiagnosticHtmlForApi(blueprintManifestStoreForApi, previewKey);
    }

    function blueprintHtmlCacheDiagnosticHtmlForApi(previewKey) {
      return blueprintStoreDiagnosticHtmlForApi(blueprintHtmlCacheStoreForApi, previewKey);
    }

    function fetchBlueprintStoreDataForApi(store, options) {
      const jsonUrl = store.url();
      return fetchBlueprintJsonForApi(jsonUrl, options).then(function (data) {
        return { data: data, url: jsonUrl };
      });
    }

    function loadBlueprintStoreForApi(store, options) {
      const existing = store.map;
      if (existing instanceof Map) {
        return Promise.resolve(existing);
      }
      const existingPromise = store.promise;
      if (existingPromise) {
        return existingPromise;
      }
      const url = store.url();
      const previousStatus = readBlueprintStoreStatusForApi(store);
      const attempts =
        Number.isFinite(previousStatus.attempts) ? previousStatus.attempts + 1 : 1;
      setBlueprintStoreStatusForApi(store, {
        state: "loading",
        attempts: attempts,
        url: url,
        lastError: "",
        entryCount: 0
      });
      let promise = null;
      promise = fetchBlueprintStoreDataForApi(store, blueprintDataLoadOptions(options))
        .then(function (result) {
          const map = store.decode(result.data);
          store.map = map;
          setBlueprintStoreStatusForApi(store, {
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
          setBlueprintStoreStatusForApi(store, {
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

    function loadBlueprintManifestForApi(options) {
      return loadBlueprintStoreForApi(blueprintManifestStoreForApi, options);
    }

    function loadBlueprintHtmlCacheForApi(options) {
      return loadBlueprintStoreForApi(blueprintHtmlCacheStoreForApi, options);
    }

    function readBlueprintStoreEntryForApi(store, previewKey) {
      if (typeof previewKey !== "string" || previewKey.length === 0) return null;
      const map = store.map;
      if (!(map instanceof Map)) return null;
      return map.get(previewKey) || null;
    }

    async function loadBlueprintStoreEntryForApi(store, previewKey, options) {
      const exact = readBlueprintStoreEntryForApi(store, previewKey);
      if (exact) return exact;
      const entryMap = await loadBlueprintStoreForApi(store, options);
      if (!(entryMap instanceof Map)) return null;
      if (typeof previewKey === "string" && previewKey.length > 0 && entryMap.has(previewKey)) {
        return entryMap.get(previewKey) || null;
      }
      return null;
    }

    async function loadBlueprintManifestEntryForApi(previewKey, options) {
      return loadBlueprintStoreEntryForApi(blueprintManifestStoreForApi, previewKey, options);
    }

    async function loadBlueprintHtmlCacheEntryForApi(previewKey, options) {
      return loadBlueprintStoreEntryForApi(blueprintHtmlCacheStoreForApi, previewKey, options);
    }

    return {
      dataUrl: blueprintDataUrlForApi,
      fetchJson: fetchBlueprintJsonForApi,
      decodeKeyedEntries: decodeBlueprintKeyedEntries,
      decodeManifest: decodeBlueprintManifest,
      decodeHtmlCache: decodeBlueprintHtmlCache,
      manifestUrl: blueprintManifestUrlForApi,
      dataApiModuleUrl: dataApiModuleUrlForApi,
      previewApiModuleUrl: previewApiModuleUrlForApi,
      graphApiModuleUrl: graphApiModuleUrlForApi,
      missingPreviewKeyDiagnosticHtml: missingPreviewKeyDiagnosticHtml,
      htmlCacheUrl: blueprintHtmlCacheUrlForApi,
      manifestStore: blueprintManifestStoreForApi,
      htmlCacheStore: blueprintHtmlCacheStoreForApi,
      defaultStoreStatus: defaultBlueprintStoreStatusForApi,
      cloneStoreStatus: cloneBlueprintStoreStatusForApi,
      readStoreStatus: readBlueprintStoreStatusForApi,
      setStoreStatus: setBlueprintStoreStatusForApi,
      readManifestStatus: readBlueprintManifestStatusForApi,
      readHtmlCacheStatus: readBlueprintHtmlCacheStatusForApi,
      storeDiagnosticHtml: blueprintStoreDiagnosticHtmlForApi,
      manifestDiagnosticHtml: blueprintManifestDiagnosticHtmlForApi,
      htmlCacheDiagnosticHtml: blueprintHtmlCacheDiagnosticHtmlForApi,
      fetchStoreData: fetchBlueprintStoreDataForApi,
      loadStore: loadBlueprintStoreForApi,
      loadManifest: loadBlueprintManifestForApi,
      loadHtmlCache: loadBlueprintHtmlCacheForApi,
      readStoreEntry: readBlueprintStoreEntryForApi,
      previewKey: previewKey,
      statementPreviewKey: statementPreviewKey,
      loadStoreEntry: loadBlueprintStoreEntryForApi,
      loadManifestEntry: loadBlueprintManifestEntryForApi,
      loadHtmlCacheEntry: loadBlueprintHtmlCacheEntryForApi,
      setDataBaseUrl: setBlueprintDataBaseUrlForApi,
      setFetchJson: setBlueprintFetchJsonForApi,
      resetStore: resetBlueprintStoreForApi,
      resetStores: resetBlueprintDataStoresForApi
    };
  }

  export function decodeBlueprintKeyedEntries(data, spec) {
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

  export function decodeBlueprintManifest(data) {
    return decodeBlueprintKeyedEntries(data, {
      arrayField: "previews",
      objectMessage: "Blueprint manifest must be an object with a previews array",
      missingArrayMessage: "Blueprint manifest is missing previews array",
      entryName: "Blueprint manifest entry",
      duplicateMessage: "Blueprint manifest contains duplicate key "
    });
  }

  export function decodeBlueprintHtmlCache(data) {
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

  export function missingPreviewKeyDiagnosticHtml() {
    return (
      "<div class=\"bp_html_cache_preview_notice\">" +
      "<p><strong>Preview key missing.</strong></p>" +
      "<p>Provide a manifest/cache preview key such as " +
      "<code>some_label--statement</code> or <code>some_label--proof</code>.</p>" +
      "</div>"
    );
  }

  export function previewKey(label, facet) {
    return corePreviewKey(label, facet);
  }

  export function statementPreviewKey(label) {
    return coreStatementPreviewKey(label);
  }

  export const previewRuntimeData = {
    createBlueprintDataApi,
    decodeBlueprintKeyedEntries,
    decodeBlueprintManifest,
    decodeBlueprintHtmlCache,
    missingPreviewKeyDiagnosticHtml,
    previewKey,
    statementPreviewKey
  };

export default previewRuntimeData;
