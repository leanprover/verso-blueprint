// One lazy Blueprint program per page, shared by the application bridges.
// Invocation and resource semantics remain VIR's; encoding stays with callers.
let readyPromise;
let program;
let disposed = false;

export async function getBlueprintProgram() {
  if (disposed) throw new Error("Blueprint VIR program is disposed");
  if (!readyPromise) {
    readyPromise = (async () => {
      const configUrl = new URL("./blueprint-vir.mjs", import.meta.url);
      const { default: config } = await import(configUrl.href);
      const { createProgram } = await import(new URL(config.runtimeModule, import.meta.url).href);
      const opened = await createProgram({
        runtimeManifestUrl: new URL(config.runtimeManifest, import.meta.url),
        programManifestUrl: new URL(config.programManifest, import.meta.url),
      });
      if (disposed) {
        opened.dispose();
        throw new Error("Blueprint VIR program is disposed");
      }
      program = opened;
      return {program, entries: config.entries};
    })();
  }
  const ready = await readyPromise;
  if (disposed) throw new Error("Blueprint VIR program is disposed");
  return ready;
}

export function disposeBlueprintProgram() {
  disposed = true;
  program?.dispose();
  program = undefined;
  readyPromise = undefined;
}

if (typeof window !== "undefined") {
  window.addEventListener("pagehide", event => {
    if (!event.persisted) disposeBlueprintProgram();
  });
}
