import { createExternalMarkupSelector } from "./selector.mjs";
import {
  externalMarkupRendererPayload,
  renderExternalMarkupSelectionInto,
} from "./-verso-data/Commands/preview-runtime-render.mjs";

const status = document.querySelector("#status");
const preview = document.querySelector("#preview");
const nodes = document.querySelector("#node");
let entries = [];
let program;

function setManifest(manifest) {
  if (!Array.isArray(manifest.previews)) throw new Error("Expected a Blueprint manifest previews array");
  entries = manifest.previews.filter(entry => Array.isArray(entry?.externalMarkup) && entry.externalMarkup.length);
  nodes.replaceChildren(...entries.map((entry, index) => {
    const option = document.createElement("option");
    option.value = String(index);
    option.textContent = entry.title || entry.authoredLabel || entry.key;
    return option;
  }));
}

try {
  const client = await (await fetch("client.json")).json();
  const { createProgram } = await import(new URL(client.runtimeModule, location.href));
  program = await createProgram({
    runtimeManifestUrl: new URL(client.runtimeManifest, location.href),
    programManifestUrl: new URL(client.programManifest, location.href),
  });
  const select = createExternalMarkupSelector(program, client.selectionEntry);
  const show = async () => {
    try {
      const entry = entries[Number(nodes.value)];
      if (!entry) throw new Error("This manifest has no external markup attachments");
      const display = document.querySelector("#display").value;
      const preference = {
        language: document.querySelector("#language").value,
        slot: document.querySelector("#slot").value,
        ...(display === "source" ? { display: "source" } : {}),
        ...(display === "callback" ? { render(payload, target) {
          const title = document.createElement("h2");
          title.textContent = `${payload.language} · ${payload.slot}`;
          const body = document.createElement("p");
          body.textContent = payload.raw;
          target.replaceChildren(title, body);
        } } : {}),
      };
      const selection = select(entry, [preference]);
      preview.replaceChildren();
      if (!selection.ok) { status.textContent = selection.reason; return; }
      const request = { label: entry.authoredLabel || entry.label, facet: entry.facet };
      await renderExternalMarkupSelectionInto(preview, selection,
        externalMarkupRendererPayload(request, entry, selection, null));
      status.textContent = `VIR selected ${selection.markup.language} · ${selection.markup.slot}`;
    } catch (error) { status.textContent = String(error.message || error); }
  };
  setManifest(await (await fetch("example.json")).json());
  document.querySelector("#controls").addEventListener("submit", event => {
    event.preventDefault();
    void show();
  });
  document.querySelector("#manifest").addEventListener("change", async event => {
    try {
      const file = event.target.files[0];
      if (!file) return;
      setManifest(JSON.parse(await file.text()));
      await show();
    } catch (error) { status.textContent = String(error.message || error); }
  });
  await show();
} catch (error) {
  program?.dispose();
  status.textContent = String(error.message || error);
}

window.addEventListener("pagehide", event => {
  // A bfcache page is retained and can resume using the same program.
  if (!event.persisted) program?.dispose();
});
