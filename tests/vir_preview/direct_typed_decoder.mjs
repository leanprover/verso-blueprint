/* Local staged experiment: specialized Verso tree and extension construction.
 * Names retain their existing codec; properties use a typed native map helper. */
const entry = "VersoBlueprintVirTests.NativeSession.DirectCodecProbe";
const previewType = "VersoBlueprint.Experimental.VirPreview.Preview";
const documentType = "VersoBlueprint.Experimental.VirPreview.Document";

export function createDirectPreviewDecoder(runtime, layouts, jsonBindings, { validate = false } = {}) {
  const definitions = new Map(layouts.map(layout => [layout.name, layout]));
  const fail = message => { throw new TypeError(message); };
  let pending;
  const track = ptr => { pending.push(ptr); return ptr; };
  const scalar = value => track(runtime.makeObjectScalar(value, "scalar"));
  const string = value => typeof value === "string" ? track(runtime.makeObjectString(value, "string")) : fail("expected string");
  const integer = (value, signed = false) => {
    if (!Number.isSafeInteger(value) || (!signed && value < 0) || Object.is(value, -0)) fail("expected safe integer");
    // Exact pinned Wasm32 Lean boxing bounds (lean.h). Larger values retain
    // the existing decimal constructor, including the safe-integer endpoints.
    const small = signed ? value >= -0x40000000 && value <= 0x3fffffff : value <= 0x7fffffff;
    return small ? scalar(value >>> 0) :
      track(runtime.makeObjectDecimal(signed ? "vir_obj_int" : "vir_obj_nat", String(value), "integer"));
  };
  // Resolve layout once per constructor. No per-node descriptor interpretation.
  const constructor = name => {
    const plan = definitions.get(name);
    if (!plan || plan.usize) fail(`missing/unsupported layout: ${name}`);
    if (plan.trivial !== null) {
      if (plan.trivial !== 0 || plan.fields.length !== 1) fail(`unsupported trivial layout: ${name}`);
      return value => value; // Already one owned root on pending.
    }
    if (!plan.objects && !plan.scalarBytes) return () => scalar(plan.tag);
    const finish = fields => {
      const count = fields.length;
      const ptr = runtime.makeObjectCtorFromOwnedFields(plan.tag, fields, name);
      pending.length -= count; // The constructor now owns these child roots.
      return track(ptr);
    };
    const finishStack = () => {
      const ptr = runtime.makeObjectCtorFromOwnedStack(plan.tag, pending, plan.objects, name);
      pending.length -= plan.objects;
      return track(ptr);
    };
    if (!plan.scalarBytes) {
      if (plan.fields.some((field, i) => field.kind !== "object" || field.index !== i))
        fail(`unsupported reordered layout: ${name}`);
      switch (plan.objects) {
        case 1: return a => runtime.makeObjectCtorFromOwnedStack ? finishStack() : finish([a]);
        case 2: return (a, b) => runtime.makeObjectCtorFromOwnedStack ? finishStack() : finish([a, b]);
        case 3: return (a, b, c) => runtime.makeObjectCtorFromOwnedStack ? finishStack() : finish([a, b, c]);
        case 4: return (a, b, c, d) => runtime.makeObjectCtorFromOwnedStack ? finishStack() : finish([a, b, c, d]);
        case 5: return (a, b, c, d, e) => runtime.makeObjectCtorFromOwnedStack ? finishStack() : finish([a, b, c, d, e]);
        case 6: return (a, b, c, d, e, f) => runtime.makeObjectCtorFromOwnedStack ? finishStack() : finish([a, b, c, d, e, f]);
        default: fail(`unsupported arity: ${name}`);
      }
    }
    // The current schema has exactly these two scalar-bearing layouts.
    const first = plan.fields[0];
    if (plan.scalarBytes !== 1 || first.kind !== "scalar" || first.offset !== 0 || first.size !== 1)
      fail(`unsupported scalar layout: ${name}`);
    const withScalar = (byte, fields) => {
      const count = fields.length;
      const ptr = runtime.makeObjectCtorFromOwnedLayout(plan.tag,
        { objectFields: fields, usizeFields: [], scalarBytes: Uint8Array.of(byte) }, name);
      pending.length -= count;
      return track(ptr);
    };
    if (plan.objects === 0 && plan.fields.length === 1) return byte => withScalar(byte, []);
    if (plan.objects === 1 && plan.fields.length === 2 && plan.fields[1].index === 0)
      return (byte, value) => withScalar(byte, [value]);
    fail(`unsupported scalar fields: ${name}`);
  };
  const inlineCtors = Object.fromEntries([...definitions.keys()].filter(name => name.startsWith("Lean.Doc.Inline."))
    .map(name => [name.split(".").at(-1), constructor(name)]));
  const blockCtors = Object.fromEntries([...definitions.keys()].filter(name => name.startsWith("Lean.Doc.Block."))
    .map(name => [name.split(".").at(-1), constructor(name)]));
  const partCtor = constructor("Lean.Doc.Part.mk"), documentCtor = constructor(`${documentType}.mk`);
  const previewCtors = Object.fromEntries(["loading", "unavailable", "ready", "error"].map(name => [name, constructor(`${previewType}.${name}`)]));
  const descCtor = constructor("Lean.Doc.DescItem.mk");
  const listCtor = constructor("Lean.Doc.ListItem.mk");
  const someCtor = constructor("Option.some");
  const timingCtor = constructor("VersoBlueprint.Experimental.VirPreview.ServerTiming.mk");
  const pairCtor = constructor("Prod.mk"), consCtor = constructor("List.cons");
  const numberingNat = constructor("Verso.Genre.Manual.Numbering.nat");
  const tagCtors = Object.fromEntries(["provided", "external", "internal"].map(kind =>
    [kind, constructor([...definitions.keys()].find(name => name.endsWith(`Verso.Genre.Manual.Tag.${kind}`)))]));
  const mixedConstructor = name => {
    const plan = definitions.get(name);
    if (!plan || plan.usize || plan.trivial !== null) fail(`unsupported mixed layout: ${name}`);
    return values => {
      const objects = new Array(plan.objects), bytes = new Uint8Array(plan.scalarBytes);
      const view = new DataView(bytes.buffer);
      plan.fields.forEach((field, i) => {
        if (field.kind === "object") objects[field.index] = values[i];
        else if (field.kind === "scalar" && field.size === 1) view.setUint8(field.offset, values[i]);
        else if (field.kind === "scalar" && field.size === 4) view.setUint32(field.offset, values[i], true);
        else fail(`unsupported field in ${name}`);
      });
      const ptr = runtime.makeObjectCtorFromOwnedLayout(plan.tag,
        { objectFields: objects, usizeFields: [], scalarBytes: bytes }, name);
      pending.length -= plan.objects;
      return track(ptr);
    };
  };
  const metadataCtor = mixedConstructor("Verso.Genre.Manual.PartMetadata.mk");
  const numberingLetter = mixedConstructor("Verso.Genre.Manual.Numbering.letter");
  const manualInlineCtor = constructor("Verso.Genre.Manual.Inline.mk");
  const manualBlockCtor = constructor("Verso.Genre.Manual.Block.mk");
  const idName = [...definitions.keys()].find(name => name.endsWith("Verso.Multi.InternalId.mk"));
  const idCtor = constructor(idName);
  const jsonCtors = Object.fromEntries(["null", "bool", "num", "str", "arr", "obj"]
    .map(name => [name, constructor(`Lean.Json.${name}`)]));
  const numberCtor = constructor("Lean.JsonNumber.mk");
  const mapCtor = constructor("Std.TreeMap.Raw.mk"), dependentMapCtor = constructor("Std.DTreeMap.Raw.mk");
  const mapInner = constructor("Std.DTreeMap.Internal.Impl.inner"), mapLeaf = constructor("Std.DTreeMap.Internal.Impl.leaf");
  // Scoped roots: no persistent cache, no memory views, and no borrowed return.
  let constants;
  const object = value => value !== null && typeof value === "object" && !Array.isArray(value) ? value : fail("expected object");
  const field = (value, name) => Object.hasOwn(object(value), name) ? value[name] : fail(`missing field: ${name}`);
  const single = value => {
    object(value);
    let found;
    for (const key in value) if (Object.hasOwn(value, key)) {
      if (found !== undefined) fail("expected one-field constructor object");
      found = key;
    }
    if (found === undefined) fail("expected one-field constructor object");
    return found;
  };
  const sequence = (value, decode) => {
    if (!Array.isArray(value)) fail("expected array");
    if (runtime.makeObjectArrayFromOwnedStack) {
      for (const child of value) decode(child);
      const ptr = runtime.makeObjectArrayFromOwnedStack(pending, value.length, "array");
      pending.length -= value.length;
      return track(ptr);
    }
    const children = [];
    for (const child of value) children.push(decode(child));
    const count = children.length;
    const ptr = runtime.makeObjectArrayFromOwnedElements(children, "array");
    pending.length -= count;
    return track(ptr);
  };
  const optionString = value => value === null ? scalar(0) : someCtor(string(value));
  const leaf = (name, value) => {
    const handle = runtime.call(`${entry}.${name}`, value);
    const cell = runtime.leanObjectHandleCell(handle, name);
    try { return track(runtime.retainLeanObjectHandleValue(handle, name)); }
    finally { runtime.releaseLeanObjectHandleCell(cell); }
  };
  const cached = (key, make, value) => {
    if (!constants.has(key)) {
      if (constants.size >= 256) return make(value);
      const ptr = make(value);
      runtime.exports.vir_obj_inc(ptr); // Separate table root from pending ownership.
      try { constants.set(key, ptr); }
      catch (error) { runtime.exports.vir_obj_dec(ptr); throw error; }
      return ptr;
    }
    const ptr = constants.get(key);
    runtime.exports.vir_obj_inc(ptr);
    return track(ptr);
  };
  const name = value => {
    if (typeof value !== "string") fail("expected name string");
    return cached(value, nameLeaf, value);
  };
  const nameLeaf = value => leaf("name", value);
  const boolTrue = () => jsonCtors.bool(1), boolFalse = () => jsonCtors.bool(0);
  const emptyProperties = value => propertiesNative(value);
  const id = value => value === null ? scalar(0) : someCtor(idCtor(integer(value)));
  // UTF-8 lexical order agrees with Unicode scalar order for well-formed text,
  // unlike JS's default UTF-16 sort when supplementary characters are present.
  const compareKeys = (a, b) => {
    let i = 0, j = 0;
    while (i < a.length && j < b.length) {
      const x = a.codePointAt(i), y = b.codePointAt(j);
      if (x !== y) return x < y ? -1 : 1;
      i += x > 0xffff ? 2 : 1; j += y > 0xffff ? 2 : 1;
    }
    return i === a.length ? (j === b.length ? 0 : -1) : 1;
  };
  const shapes = new Map(); // JS-only plans; no pointers retained across updates.
  const sortedKeys = value => {
    const keys = Object.keys(value);
    const signature = keys.map(key => `${key.length}:${key}`).join("");
    const cached = shapes.get(signature);
    if (cached) return cached;
    keys.sort(compareKeys);
    if (keys.length <= 32 && signature.length <= 2048 && shapes.size < 256) shapes.set(signature, keys);
    return keys;
  };
  const tree = (value, keys, lo, hi) => {
    if (lo === hi) return mapLeaf();
    const middle = (lo + hi) >>> 1, key = keys[middle];
    return mapInner(integer(hi - lo), string(key), json(value[key]),
      tree(value, keys, lo, middle), tree(value, keys, middle + 1, hi));
  };
  const json = value => {
    if (value === null) return jsonCtors.null();
    switch (typeof value) {
      case "boolean": return cached(value, value ? boolTrue : boolFalse);
      case "number": return jsonCtors.num(numberCtor(integer(value, true), integer(0)));
      case "string": return jsonCtors.str(string(value));
      case "object": {
        if (Array.isArray(value)) return jsonCtors.arr(sequence(value, json));
        const keys = sortedKeys(value);
        // This experimental adapter builds a size-balanced raw map from sorted
        // unique keys. Its layout is generated, but this container algorithm is
        // pinned implementation knowledge, not a public generic codec promise.
        return jsonCtors.obj(mapCtor(dependentMapCtor(tree(value, keys, 0, keys.length))));
      }
      default: fail("unchecked JSON value");
    }
  };
  const manualInline = value => manualInlineCtor(name(field(value, "name")), id(field(value, "id")),
    json(field(value, "data")));
  const propertiesNative = value => {
    const ptr = sequence(Object.entries(object(value)), pair => pairCtor(string(pair[0]), string(pair[1])));
    let input, output;
    try {
      input = runtime.makeLeanObjectHandleResource(ptr, "property entries");
      const result = runtime.call(`${entry}.propertiesNative`, input);
      const cell = runtime.leanObjectHandleCell(result, "property map");
      try { output = runtime.retainLeanObjectHandleValue(result, "property map"); }
      finally { runtime.releaseLeanObjectHandleCell(cell); }
    } finally {
      if (input) runtime.releaseLeanObjectHandleCell(runtime.leanObjectHandleCell(input, "property entries"));
      pending.pop(); runtime.exports.vir_obj_dec(ptr);
    }
    return track(output);
  };
  const properties = value => {
      const properties = field(value, "properties");
      return Object.keys(object(properties)).length === 0
        ? cached(emptyProperties, emptyProperties, properties) : propertiesNative(properties);
  };
  const boolean = value => typeof value === "boolean" ? +value : fail("expected boolean");
  const optional = (value, decode) => value === null ? scalar(0) : someCtor(decode(value));
  const tag = value => {
    const kind = single(value);
    if (!Object.hasOwn(tagCtors, kind)) fail("unknown tag");
    const text = field(value[kind], "name");
    if (kind === "external" && (typeof text !== "string" || !/^[a-zA-Z0-9_-]*$/.test(text))) fail("invalid slug");
    return tagCtors[kind](string(text));
  };
  const numbering = value => {
    if (typeof value === "number") return numberingNat(integer(value));
    if (typeof value !== "string" || [...value].length !== 1) fail("expected one character");
    return numberingLetter([value.codePointAt(0)]);
  };
  const metadata = value => {
    if (value === null) return scalar(0);
    object(value);
    const get = (key, fallback) => Object.hasOwn(value, key) ? value[key] : fallback;
    const authors = field(value, "authors");
    if (!Array.isArray(authors)) fail("expected authors array");
    const list = i => i === authors.length ? scalar(0) : consCtor(string(authors[i]), list(i + 1));
    const split = field(value, "htmlSplit"), priority = field(value, "searchPriority");
    if (split !== "default" && split !== "never") fail("unknown HTML split mode");
    if (!Number.isInteger(priority) || priority < 0 || priority >= 100) fail("invalid search priority");
    return someCtor(metadataCtor([
      optionString(get("shortTitle", null)), optionString(get("shortContextTitle", null)), list(0),
      optionString(get("authorshipNote", null)), optionString(get("date", null)), optional(get("tag", null), tag),
      optionString(get("file", null)), id(get("id", null)), boolean(field(value, "number")), boolean(field(value, "draft")),
      optional(get("assignedNumber", null), numbering), boolean(field(value, "htmlToc")),
      definitions.get(`Verso.Genre.Manual.HtmlSplitMode.${split}`).tag, integer(priority),
    ]));
  };
  const serverTiming = value => optional(value, v => timingCtor(integer(field(v, "snapshotWaitNanos")),
    integer(field(v, "checkedWaitNanos")), integer(field(v, "evaluationNanos"))));
  const manualBlock = value => manualBlockCtor(name(field(value, "name")), id(field(value, "id")),
    json(field(value, "data")), properties(value));
  const inline = value => {
    const kind = single(value), v = value[kind];
    switch (kind) {
      case "text": case "code": case "linebreak": return inlineCtors[kind](string(v));
      case "emph": case "bold": case "concat": return inlineCtors[kind](sequence(v, inline));
      case "math": {
        const mode = field(v, "mode");
        if (mode !== "inline" && mode !== "display") fail("unsupported math mode");
        return inlineCtors.math(definitions.get(`Lean.Doc.MathMode.${mode}`).tag, string(field(v, "str")));
      }
      case "link": return inlineCtors.link(sequence(field(v, "content"), inline), string(field(v, "url")));
      case "footnote": return inlineCtors.footnote(string(field(v, "name")), sequence(field(v, "content"), inline));
      case "image": return inlineCtors.image(string(field(v, "alt")), string(field(v, "url")));
      case "other": return inlineCtors.other(manualInline(field(v, "container")), sequence(field(v, "content"), inline));
      default: fail(`unknown inline: ${kind}`);
    }
  };
  const block = value => {
    object(value);
    // Preserve Verso Block.fromJson?'s constructor precedence (not single-key).
    const kind = Object.hasOwn(value, "para") ? "para" : Object.hasOwn(value, "code") ? "code" :
      Object.hasOwn(value, "ul") ? "ul" : Object.hasOwn(value, "ol") ? "ol" :
      Object.hasOwn(value, "dl") ? "dl" : Object.hasOwn(value, "blockquote") ? "blockquote" :
      Object.hasOwn(value, "concat") ? "concat" : "other";
    const v = value[kind];
    switch (kind) {
      case "para": return blockCtors.para(sequence(v, inline));
      case "code": return blockCtors.code(string(v));
      case "ul": return blockCtors.ul(sequence(v, listItem));
      case "ol": return blockCtors.ol(integer(field(v, "start"), true), sequence(field(v, "items"), listItem));
      case "dl": return blockCtors.dl(sequence(v, descItem));
      case "blockquote": case "concat": return blockCtors[kind](sequence(v, block));
      case "other": return blockCtors.other(manualBlock(field(v, "container")), sequence(field(v, "content"), block));
      default: fail("expected block constructor");
    }
  };
  const listItem = item => listCtor(sequence(field(item, "contents"), block));
  const descItem = item => descCtor(sequence(field(item, "term"), inline), sequence(field(item, "contents"), block));
  const part = value => partCtor(sequence(field(value, "title"), inline), string(field(value, "titleString")),
    metadata(field(value, "metadata")), sequence(field(value, "content"), block),
    sequence(field(value, "subParts"), part));
  const document = value => documentCtor(integer(field(value, "version")),
    string(field(value, "correlationId")), string(field(value, "cursorToken")),
    optionString(Object.hasOwn(value, "focus") ? value.focus : null),
    serverTiming(Object.hasOwn(value, "serverTiming") ? value.serverTiming : null),
    part(field(value, "document")));
  return input => {
    if (runtime.disposed || runtime.disposing) fail("runtime disposed");
    if (constants) fail("nested direct conversion");
    if (validate) {
      const checked = jsonBindings["jsonValue.check"](input);
      if (checked.kind !== "ok") fail(checked.value);
    }
    const kind = single(input), v = input[kind];
    if (!Object.hasOwn(previewCtors, kind)) fail("unknown preview constructor");
    constants = new Map();
    pending = [];
    let handle, ptr;
    try {
      ptr = previewCtors[kind](kind === "ready" ? document(field(v, "document")) : string(field(v, "message")));
      handle = runtime.makeLeanObjectHandleResource(ptr, "typed preview");
      return runtime.call(`${entry}.finish`, handle);
    } finally {
      if (handle) runtime.releaseLeanObjectHandleCell(runtime.leanObjectHandleCell(handle, "typed preview"));
      runtime.releaseOwnedObjects(pending);
      pending = undefined;
      for (const ptr of constants.values()) runtime.exports.vir_obj_dec(ptr);
      constants = undefined;
    }
  };
}
