/* Local staged experiment: specialized Verso tree and extension construction.
 * Small metadata/property-map leaves retain their exact existing Lean codecs. */
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
    if (!plan.scalarBytes) {
      if (plan.fields.some((field, i) => field.kind !== "object" || field.index !== i))
        fail(`unsupported reordered layout: ${name}`);
      switch (plan.objects) {
        case 1: return a => finish([a]);
        case 2: return (a, b) => finish([a, b]);
        case 3: return (a, b, c) => finish([a, b, c]);
        case 4: return (a, b, c, d) => finish([a, b, c, d]);
        case 5: return (a, b, c, d, e) => finish([a, b, c, d, e]);
        case 6: return (a, b, c, d, e, f) => finish([a, b, c, d, e, f]);
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
  const single = value => { const keys = Object.keys(object(value)); if (keys.length !== 1) fail("expected one-field constructor object"); return keys[0]; };
  const sequence = (value, decode) => {
    if (!Array.isArray(value)) fail("expected array");
    const children = [];
    for (const child of value) children.push(decode(child));
    const count = children.length;
    const ptr = runtime.makeObjectArrayFromOwnedElements(children, "array");
    pending.length -= count;
    return track(ptr);
  };
  const optionString = value => value === null ? scalar(0) : someCtor(string(value));
  const leaf = (name, value) => {
    if (value === null && (name === "metadata" || name === "serverTiming"))
      return scalar(0);
    const handle = runtime.call(`${entry}.${name}`, value);
    const cell = runtime.leanObjectHandleCell(handle, name);
    try { return track(runtime.retainLeanObjectHandleValue(handle, name)); }
    finally { runtime.releaseLeanObjectHandleCell(cell); }
  };
  const cached = (key, make) => {
    if (!constants.has(key)) {
      if (constants.size >= 256) return make();
      const ptr = make();
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
    return cached(`name:${value}`, () => leaf("name", value));
  };
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
      case "boolean": return cached(`json-bool:${value}`, () => jsonCtors.bool(value ? 1 : 0));
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
  const properties = value => {
      const properties = field(value, "properties");
      return Object.keys(object(properties)).length === 0
        ? cached("empty-properties", () => leaf("properties", properties)) : leaf("properties", properties);
  };
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
    const kind = ["para", "code", "ul", "ol", "dl", "blockquote", "concat", "other"].find(key => Object.hasOwn(value, key));
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
    leaf("metadata", field(value, "metadata")), sequence(field(value, "content"), block),
    sequence(field(value, "subParts"), part));
  const document = value => documentCtor(integer(field(value, "version")),
    string(Object.hasOwn(value, "correlationId") ? value.correlationId : ""),
    string(Object.hasOwn(value, "cursorToken") ? value.cursorToken : ""),
    optionString(Object.hasOwn(value, "focus") ? value.focus : null),
    leaf("serverTiming", Object.hasOwn(value, "serverTiming") ? value.serverTiming : null),
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
