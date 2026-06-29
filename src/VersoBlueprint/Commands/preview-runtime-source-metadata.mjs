// Source metadata lookup.
//
// The manifest owns source provenance. This module only resolves each
// `entry.sources[*].document` through the data API and returns structured data.
// Rendering source previews remains a Blueprint/Verso responsibility.

function trimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
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

// Render results can also carry `key`; require manifest-entry fields before
// treating an object as an entry instead of looking it up by key.
function manifestEntryLike(source) {
  if (!source || typeof source !== "object" || Array.isArray(source)) return false;
  if (!trimmedString(source.key)) return false;
  return (
    typeof source.authoredLabel === "string" ||
    typeof source.targetKind === "string" ||
    typeof source.facet === "string" ||
    Array.isArray(source.sources) ||
    Array.isArray(source.externalMarkup) ||
    Array.isArray(source.leanCodePreviewKeys)
  );
}

function sourceMetadataEntryFromInput(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return null;
  if (manifestEntryLike(input.manifestEntry)) {
    return input.manifestEntry;
  }
  if (manifestEntryLike(input)) return input;
  return null;
}

function sourceMetadataKeyFromInput(input) {
  const directKey = trimmedString(input);
  if (directKey) return directKey;
  if (!input || typeof input !== "object" || Array.isArray(input)) return "";
  return trimmedString(input.key);
}

async function loadManifestEntry(previewKey, options) {
  const dataApi = requireBlueprintDataApi(options);
  return dataApi.loadManifestEntry(previewKey, options);
}

async function resolveSourceMetadataEntry(source, options) {
  const entry = sourceMetadataEntryFromInput(source);
  if (entry) {
    return {
      ok: true,
      key: trimmedString(entry.key),
      reason: "",
      manifestEntry: entry
    };
  }
  const key = sourceMetadataKeyFromInput(source);
  if (!key) {
    return {
      ok: false,
      key: "",
      reason: "missing-key",
      manifestEntry: null
    };
  }
  const manifestEntry = await loadManifestEntry(key, options);
  if (!manifestEntry) {
    return {
      ok: false,
      key,
      reason: "manifest-entry-missing",
      manifestEntry: null
    };
  }
  return {
    ok: true,
    key,
    reason: "",
    manifestEntry
  };
}

async function resolveSourceRefs(sourceRefs, options) {
  const refs = Array.isArray(sourceRefs) ? sourceRefs : [];
  const dataApi = requireBlueprintDataApi(options);
  const documentIds = Array.from(new Set(refs.map(function (ref) {
    return trimmedString(ref && ref.document);
  }).filter(Boolean)));
  const documentsById = new Map();
  await Promise.all(documentIds.map(async function (documentId) {
    documentsById.set(documentId, await dataApi.loadSourceDocument(documentId, options));
  }));
  return refs.map(function (ref) {
    const sourceRef = ref && typeof ref === "object" ? ref : {};
    const documentId = trimmedString(sourceRef.document);
    return {
      sourceRef,
      documentId,
      document: documentId ? (documentsById.get(documentId) || null) : null,
      spans: Array.isArray(sourceRef.spans) ? sourceRef.spans : []
    };
  });
}

export async function resolveSourceMetadata(source, options) {
  const opts = options && typeof options === "object" ? options : {};
  const entryResult = await resolveSourceMetadataEntry(source, opts);
  if (!entryResult.ok) {
    return Object.assign({}, entryResult, {
      sources: []
    });
  }
  const manifestEntry = entryResult.manifestEntry;
  const sourceRefs =
    manifestEntry && Array.isArray(manifestEntry.sources) ? manifestEntry.sources : [];
  if (sourceRefs.length === 0) {
    return {
      ok: false,
      key: entryResult.key,
      reason: "source-missing",
      manifestEntry,
      sources: []
    };
  }
  return {
    ok: true,
    key: entryResult.key,
    reason: "",
    manifestEntry,
    sources: await resolveSourceRefs(sourceRefs, opts)
  };
}

export const previewRuntimeSourceMetadata = {
  resolveSourceMetadata
};

export default previewRuntimeSourceMetadata;
