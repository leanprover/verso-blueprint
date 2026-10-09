import { createExternalMarkupSelector } from "./selector.mjs";
import {
  externalMarkupRendererPayload,
  renderExternalMarkupSelectionInto,
} from "./-verso-data/Commands/preview-runtime-render.mjs";

const status = document.querySelector("#status");
const preview = document.querySelector("#preview");
const nodes = document.querySelector("#node");
const filter = document.querySelector("#filter");
let entries = [];
let program;
let manifestRead = 0;

const attachments = entry => Array.isArray(entry?.externalMarkup) ? entry.externalMarkup : [];
const nodeName = entry => entry.authoredLabel || entry.label || entry.key || "(unnamed entry)";
const selectedEntry = () => nodes.value === "" ? null : entries[Number(nodes.value)];

function renderNames(preferred = nodes.value) {
  const query = filter.value.trim().toLowerCase();
  const fragment = document.createDocumentFragment();
  let count = 0;
  entries.forEach((entry, index) => {
    const name = nodeName(entry);
    if (![name, entry.title, entry.key, entry.facet].some(value =>
      typeof value === "string" && value.toLowerCase().includes(query))) return;
    const option = document.createElement("option");
    option.value = String(index);
    const facet = entry.facet ? ` [${entry.facet}]` : "";
    const title = entry.title && entry.title !== name ? ` — ${entry.title}` : "";
    option.textContent = `${name}${facet}${title} · ${attachments(entry).length} attachments`;
    fragment.appendChild(option);
    count++;
  });
  nodes.replaceChildren(fragment);
  nodes.value = preferred;
  if (nodes.selectedIndex < 0 && nodes.options.length) nodes.selectedIndex = 0;
  document.querySelector("#node-count").textContent = `${count} of ${entries.length} entries`;
  document.querySelector("#render").disabled = !selectedEntry();
  return nodes.value !== preferred;
}

function showNodeInfo(entry) {
  const markups = attachments(entry);
  document.querySelector("#node-info").textContent = !entry ? "" :
    `${entry.key || nodeName(entry)} · Available: ${markups.length ? markups.map(markup =>
      `${markup?.language || "any language"} / ${markup?.slot || "default slot"}`).join(", ") : "no external markup"}`;
  const slots = document.createDocumentFragment();
  for (const slot of new Set(markups.map(markup => markup?.slot).filter(value => typeof value === "string"))) {
    const option = document.createElement("option");
    option.value = slot;
    slots.appendChild(option);
  }
  document.querySelector("#slots").replaceChildren(slots);
}

function setManifest(manifest) {
  if (!Array.isArray(manifest?.previews)) throw new Error("Expected a Blueprint manifest previews array");
  entries = manifest.previews.filter(entry => entry && typeof entry === "object" && !Array.isArray(entry));
  filter.value = "";
  // Keep every name visible, but initially select an entry this example can show.
  renderNames(String(Math.max(0, entries.findIndex(entry => attachments(entry).length))));
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
      const entry = selectedEntry();
      preview.replaceChildren();
      showNodeInfo(entry);
      if (!entry) {
        status.textContent = entries.length ? "No matching names" : "This manifest has no entries";
        return;
      }
      if (!attachments(entry).length) {
        status.textContent = `No external markup attached to ${nodeName(entry)}; native previews are outside this example.`;
        return;
      }
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
      if (!selection.ok) { status.textContent = selection.reason; return; }
      const request = { label: entry.authoredLabel || entry.label, facet: entry.facet };
      await renderExternalMarkupSelectionInto(preview, selection,
        externalMarkupRendererPayload(request, entry, selection, null));
      status.textContent = `VIR selected ${selection.markup.language} · ${selection.markup.slot}`;
    } catch (error) {
      preview.replaceChildren();
      status.textContent = String(error.message || error);
    }
  };
  setManifest(await (await fetch("example.json")).json());
  document.querySelector("#controls").addEventListener("submit", event => {
    event.preventDefault();
    void show();
  });
  nodes.addEventListener("change", () => { void show(); });
  filter.addEventListener("input", () => {
    if (renderNames()) void show();
  });
  document.querySelector("#manifest").addEventListener("change", async event => {
    const read = ++manifestRead;
    try {
      const file = event.target.files[0];
      if (!file) return;
      const text = await file.text();
      if (read !== manifestRead) return;
      setManifest(JSON.parse(text));
      await show();
    } catch (error) {
      if (read !== manifestRead) return;
      preview.replaceChildren();
      status.textContent = String(error.message || error);
    }
  });
  document.querySelectorAll("fieldset").forEach(fieldset => { fieldset.disabled = false; });
  await show();
} catch (error) {
  program?.dispose();
  status.textContent = String(error.message || error);
}

window.addEventListener("pagehide", event => {
  // A bfcache page is retained and can resume using the same program.
  if (!event.persisted) program?.dispose();
});
