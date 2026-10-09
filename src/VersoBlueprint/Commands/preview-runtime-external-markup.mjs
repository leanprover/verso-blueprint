// Browser-owned normalization, callback availability and object identities.
// Matching and failure precedence are implemented only by the Lean program.
import { getBlueprintProgram } from "./blueprint-vir-client.mjs";

const isObject = value => value !== null && typeof value === "object";

export function normalizeExternalMarkupPreferences(value) {
  if (!isObject(value)) return [];
  if (Array.isArray(value)) return value;
  if (Array.isArray(value.prefer)) return value.prefer;
  return [value];
}

export function normalizeExternalMarkupToken(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

export function externalMarkupPreferenceDisplay(preference) {
  return normalizeExternalMarkupToken(preference && preference.display);
}

export function externalMarkupPreferenceCanRender(preference) {
  return isObject(preference) && (typeof preference.render === "function" ||
    externalMarkupPreferenceDisplay(preference) === "source");
}

// Source bodies, opaque metadata and callbacks stay in their original arrays.
export function selectionInput(entry, preferences) {
  const markups = Array.isArray(entry?.externalMarkup) ? entry.externalMarkup : [];
  return {
    markups: Array.from(markups, markup => ({
      language: normalizeExternalMarkupToken(isObject(markup) ? markup.language : ""),
      slot: isObject(markup) ? String(markup.slot || "").trim() : "",
      hasContent: isObject(markup) && typeof markup.raw === "string" && markup.raw.length > 0,
    })),
    preferences: Array.from(preferences, preference => ({
      language: normalizeExternalMarkupToken(isObject(preference) ? preference.language : ""),
      slot: isObject(preference) && typeof preference.slot === "string" ? preference.slot.trim() : "",
      canRender: externalMarkupPreferenceCanRender(preference),
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

// The common client owns the program; this bridge only owns its value boundary.
export async function selectExternalMarkup(entry, preferences) {
  const {program, entries} = await getBlueprintProgram();
  return createExternalMarkupSelector(program, entries.externalMarkup)(entry, preferences);
}
