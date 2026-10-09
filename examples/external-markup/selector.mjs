import {
  externalMarkupPreferenceCanRender,
  normalizeExternalMarkupToken,
} from "./-verso-data/Commands/preview-runtime-render.mjs";

const isObject = value => value !== null && typeof value === "object";

// Only matching descriptors cross the value boundary. Source bodies, opaque
// metadata and callback identities stay in their original JS arrays.
export function selectionInput(entry, preferences) {
  const markups = Array.isArray(entry?.externalMarkup) ? entry.externalMarkup : [];
  return {
    markups: markups.map(markup => ({
      language: normalizeExternalMarkupToken(isObject(markup) ? markup.language : ""),
      slot: isObject(markup) ? String(markup.slot || "").trim() : "",
      hasContent: isObject(markup) && typeof markup.raw === "string" && markup.raw.length > 0,
    })),
    preferences: preferences.map(preference => ({
      language: normalizeExternalMarkupToken(isObject(preference) ? preference.language : ""),
      slot: isObject(preference) && typeof preference.slot === "string" ? preference.slot.trim() : "",
      canRender: !!externalMarkupPreferenceCanRender(preference),
      enabled: isObject(preference),
    })),
  };
}

export function createExternalMarkupSelector(program, entryName) {
  return (entry, preferences) => {
    const markups = Array.isArray(entry?.externalMarkup) ? entry.externalMarkup : [];
    const result = JSON.parse(program.call(entryName, JSON.stringify(selectionInput(entry, preferences))));
    if (!isObject(result) || Array.isArray(result)) {
      throw new Error("VIR returned an invalid external markup selection");
    }
    if (typeof result.error === "string") throw new Error(result.error);
    const at = (values, index) => {
      if (index === null) return null;
      if (!Number.isSafeInteger(index) || index < 0 || index >= values.length) {
        throw new Error("VIR returned an invalid external markup selection index");
      }
      return values[index];
    };
    if (typeof result.ok !== "boolean" || typeof result.reason !== "string") {
      throw new Error("VIR returned an invalid external markup selection");
    }
    const selected = {
      ok: result.ok,
      markup: at(markups, result.markupIndex),
      preference: at(preferences, result.preferenceIndex),
    };
    const isMatch = selected.markup !== null && selected.preference !== null;
    const valid = result.ok ? isMatch && result.reason === "" :
      (result.reason === "external-markup-renderer-missing" ? isMatch :
        result.reason === "external-markup-missing" && selected.markup === null);
    if (!valid) throw new Error("VIR returned an invalid external markup selection");
    return result.ok ? selected : { ...selected, reason: result.reason };
  };
}
