import { getBlueprintProgram } from "./blueprint-vir-client.mjs";

function requireBlueprintDataApi(options) {
  const dataApi = options.dataApi && typeof options.dataApi === "object" ? options.dataApi : null;
  if (!dataApi) {
    throw new Error("Blueprint data API missing; call through createPreview() or createBlueprintDataApi()");
  }
  return dataApi;
}

// Lean owns entry selection and reference normalization. The host owns fetching
// and reattaches original objects; it never exposes serialized entry/span clones.
export async function resolveSourceMetadata(source, options) {
  const opts = options && typeof options === "object" ? options : {};
  const sourceJson = JSON.stringify(source) ?? "null";
  const { program, entries } = await getBlueprintProgram();
  const inspect = entry => {
    const output = JSON.parse(program.call(entries.manifestInspectSource, sourceJson,
      JSON.stringify(entry)));
    if (!output.ok) throw new Error(output.error || "Source metadata resolution failed");
    if (output.abiVersion !== 1 || output.results?.length !== 1 ||
        output.results[0].kind !== "sourceMetadata" || output.results[0].requestId !== "source") {
      throw new Error("Invalid source metadata response");
    }
    return output.results[0];
  };
  let result = inspect(null);
  let fetchedEntry = null;
  if (result.reason === "manifest-entry-missing") {
    fetchedEntry = await requireBlueprintDataApi(opts).loadManifestEntry(result.key, opts);
    if (fetchedEntry) result = inspect(fetchedEntry);
  }
  const manifestEntry = !result.manifestEntry ? null :
    result.inputEntryIsNested === true ? source.manifestEntry :
    result.inputEntryIsNested === false ? source : fetchedEntry;
  if (result.manifestEntry && !manifestEntry) throw new Error("Source entry missing from host");
  const resolved = { ok: result.ok, key: result.key, reason: result.reason, manifestEntry, sources: [] };
  if (!result.ok) return resolved;
  const refs = manifestEntry.sources;
  if (!Array.isArray(refs) || refs.length !== result.sources.length) {
    throw new Error("Source reference count mismatch");
  }
  const dataApi = requireBlueprintDataApi(opts);
  const documents = new Map();
  const ids = [...new Set(result.sources.map(ref => ref.documentId).filter(Boolean))];
  await Promise.all(ids.map(async id => documents.set(id, await dataApi.loadSourceDocument(id, opts))));
  return {
    ...resolved,
    sources: result.sources.map((ref, index) => {
      const original = refs[index];
      const sourceRef = original && typeof original === "object" ? original : {};
      return { sourceRef, documentId: ref.documentId, document: documents.get(ref.documentId) || null,
        spans: Array.isArray(sourceRef.spans) ? sourceRef.spans : [] };
    }),
  };
}

export const previewRuntimeSourceMetadata = {
  resolveSourceMetadata
};

export default previewRuntimeSourceMetadata;
