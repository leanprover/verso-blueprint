import { getBlueprintProgram } from "./blueprint-vir-client.mjs";

// Only transfer and identity projection live here; the selection policy is Lean.
export async function prepareManifestResolver(manifest, previews) {
  const input = JSON.stringify({ abiVersion: 1, manifest });
  const { program, entries } = await getBlueprintProgram();
  const prepared = program.call(entries.manifestPrepare, input);
  return {
    resolve(requests) {
      if (requests.some(request => request.kind !== "label" && request.kind !== "declaration")) {
        throw new Error("The browser resolver supports label and declaration requests");
      }
      const output = JSON.parse(program.call(entries.manifestLookup, prepared,
        JSON.stringify({ abiVersion: 1, requests })));
      if (!output.ok) throw new Error(output.error || "Manifest resolution failed");
      if (!Array.isArray(output.results) || output.results.length !== requests.length) {
        throw new Error("Invalid manifest resolver response");
      }
      return output.results.map((result, index) => {
        if (result.requestId !== requests[index].id || result.kind !== requests[index].kind) {
          throw new Error("Mismatched manifest resolver response");
        }
        const entry = result.manifestEntry
          ? previews.get(result.manifestEntry.key.trim()) : null;
        if (result.manifestEntry && !entry) throw new Error("Resolved manifest entry missing from host");
        return {
          ok: result.ok,
          reason: result.reason,
          key: result.key,
          ...(result.kind === "label" ? { label: result.label, facet: result.facet } :
            { declaration: result.declaration }),
          manifestEntry: entry,
          href: result.href,
          sourceLocation: entry ? entry.sourceLocation : result.sourceLocation,
        };
      });
    },
  };
}
