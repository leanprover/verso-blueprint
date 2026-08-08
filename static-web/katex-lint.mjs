import { pathToFileURL } from "node:url";
import { createInterface } from "node:readline";

function sanitizeMessage(message) {
  return String(message ?? "")
    .replace(/\u0332/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function readPayload(raw) {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function loadKatex(katexPath) {
  if (!katexPath) return null;
  try {
    const katexModule = await import(pathToFileURL(katexPath).href);
    return katexModule.default ?? katexModule;
  } catch {
    return null;
  }
}

function toCodepointIndex(input, utf16Index) {
  return Array.from(input.slice(0, utf16Index)).length;
}

function toCodepointLength(input, utf16Start, utf16Length) {
  return Array.from(input.slice(utf16Start, utf16Start + utf16Length)).length;
}

function renderError(
  error,
  input,
  { sourceText = null, sourceOffsetUtf16 = 0, inPrelude = null } = {}
) {
  const positionUtf16 =
    typeof error === "object" &&
    error !== null &&
    typeof error.position === "number"
      ? error.position
      : null;
  const lengthUtf16 =
    typeof error === "object" &&
    error !== null &&
    typeof error.length === "number"
      ? error.length
      : null;
  const resolvedPrelude =
    typeof inPrelude === "boolean"
      ? inPrelude
      : typeof positionUtf16 === "number" && positionUtf16 < sourceOffsetUtf16;
  const position =
    typeof positionUtf16 === "number"
      ? toCodepointIndex(input, positionUtf16)
      : null;
  const length =
    typeof positionUtf16 === "number" && typeof lengthUtf16 === "number"
      ? toCodepointLength(input, positionUtf16, lengthUtf16)
      : null;
  const sourcePosition =
    sourceText !== null &&
    !resolvedPrelude &&
    typeof positionUtf16 === "number"
      ? toCodepointIndex(sourceText, Math.max(positionUtf16 - sourceOffsetUtf16, 0))
      : null;
  const sourceLength =
    sourceText !== null &&
    !resolvedPrelude &&
    typeof positionUtf16 === "number" &&
    typeof lengthUtf16 === "number"
      ? toCodepointLength(
          sourceText,
          Math.max(positionUtf16 - sourceOffsetUtf16, 0),
          lengthUtf16
        )
      : null;
  const message = sanitizeMessage(
    typeof error === "object" &&
      error !== null &&
      typeof error.rawMessage === "string"
      ? error.rawMessage
      : error instanceof Error
        ? error.message
        : String(error)
  );
  return {
    ok: false,
    message,
    position,
    length,
    sourcePosition,
    sourceLength,
    inPrelude: resolvedPrelude,
  };
}

function renderSuccess() {
  return {
    ok: true,
    message: "",
    position: null,
    length: null,
    sourcePosition: null,
    sourceLength: null,
    inPrelude: false,
  };
}

function lintPayload(payload, katex, preludeCache = null) {
  if (!payload || typeof payload.source !== "string") return null;

  const texPrelude =
    typeof payload.texPrelude === "string" ? payload.texPrelude.trim() : "";
  const source = payload.source;
  const displayMode = payload.mode === "display";
  const combinedInput = texPrelude ? `${texPrelude}\n${source}` : source;
  const sourceOffset = texPrelude ? texPrelude.length + 1 : 0;

  let preludeError = null;
  if (texPrelude && preludeCache?.has(texPrelude)) {
    preludeError = preludeCache.get(texPrelude);
  } else if (texPrelude) {
    try {
      katex.renderToString(texPrelude, {
        throwOnError: true,
        displayMode: false,
      });
    } catch (error) {
      preludeError = renderError(error, texPrelude, { inPrelude: true });
    }
    preludeCache?.set(texPrelude, preludeError);
  }

  if (preludeError) return preludeError;

  try {
    katex.renderToString(combinedInput, { throwOnError: true, displayMode });
    return renderSuccess();
  } catch (error) {
    return renderError(error, combinedInput, {
      sourceText: source,
      sourceOffsetUtf16: sourceOffset,
    });
  }
}

async function runOneShot() {
  const payload = readPayload(process.argv[2] ?? "");
  const katex = await loadKatex(process.argv[3] ?? "");
  if (!katex || typeof katex.renderToString !== "function") return false;
  const result = lintPayload(payload, katex);
  if (!result) return false;
  process.stdout.write(JSON.stringify(result));
  return true;
}

async function runWorker() {
  const katex = await loadKatex(process.argv[3] ?? "");
  if (!katex || typeof katex.renderToString !== "function") return false;

  const preludeCache = new Map();
  const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
  for await (const raw of lines) {
    const result = lintPayload(readPayload(raw), katex, preludeCache);
    if (!result) {
      lines.close();
      return false;
    }
    process.stdout.write(`${JSON.stringify(result)}\n`);
  }
  return true;
}

const ok =
  process.argv[2] === "--worker" ? await runWorker() : await runOneShot();
if (!ok) {
  process.exitCode = 1;
}
