/* Local staged experiment: specialized Verso tree and extension construction.
 * Small metadata/property-map leaves retain their exact existing Lean codecs. */
const entry = "VersoBlueprintVirTests.NativeSession.DirectCodecProbe";
const previewType = "VersoBlueprint.Experimental.VirPreview.Preview";
const documentType = "VersoBlueprint.Experimental.VirPreview.Document";

export function createDirectPreviewDecoder(runtime, layouts, jsonBindings) {
  const definitions = new Map(layouts.map(layout => [layout.name, layout]));
  const fail = message => { throw new TypeError(message); };
  const string = value => typeof value === "string" ? runtime.makeObjectString(value, "string") : fail("expected string");
  const integer = (value, signed = false) => {
    if (!Number.isSafeInteger(value) || (!signed && value < 0) || Object.is(value, -0)) fail("expected safe integer");
    return runtime.makeObjectDecimal(signed ? "vir_obj_int" : "vir_obj_nat", String(value), "integer");
  };
  // Resolve layout once per constructor. No per-node descriptor interpretation.
  const constructor = name => {
    const plan = definitions.get(name);
    if (!plan || plan.usize) fail(`missing/unsupported layout: ${name}`);
    const writers = plan.fields.map(field => {
      if (field.kind === "object") return (layout, make) => { layout.objectFields[field.index] = make(); };
      if (field.kind === "scalar" && field.size === 1)
        return (layout, make) => { layout.scalarBytes[field.offset] = make(); };
      fail(`unsupported field layout: ${name}`);
    });
    return (...values) => {
      if (values.length !== writers.length) fail(`field count: ${name}`);
      if (plan.trivial !== null) return values[plan.trivial]();
      if (!plan.objects && !plan.scalarBytes) return runtime.makeObjectScalar(plan.tag, name);
      const layout = { objectFields: Array(plan.objects).fill(0), usizeFields: [], scalarBytes: new Uint8Array(plan.scalarBytes) };
      try {
        writers.forEach((write, index) => write(layout, values[index]));
        return runtime.makeObjectCtorFromOwnedLayout(plan.tag, layout, name);
      } finally { runtime.releaseOwnedObjects(layout.objectFields); }
    };
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
    try {
      for (const child of value) children.push(decode(child));
      return runtime.makeObjectArrayFromOwnedElements(children, "array");
    } finally { runtime.releaseOwnedObjects(children); }
  };
  const optionString = value => value === null ? runtime.makeObjectScalar(0, "none") :
    runtime.makeObjectValue({ interfaceTag: 18, element: { interfaceTag: 3 } }, value, "optional string");
  const leaf = (name, value) => {
    if (value === null && (name === "metadata" || name === "serverTiming"))
      return runtime.makeObjectScalar(0, "none");
    const handle = runtime.call(`${entry}.${name}`, value);
    const cell = runtime.leanObjectHandleCell(handle, name);
    try { return runtime.retainLeanObjectHandleValue(handle, name); }
    finally { runtime.releaseLeanObjectHandleCell(cell); }
  };
  const cached = (key, make) => {
    if (!constants.has(key)) {
      if (constants.size >= 256) return make();
      constants.set(key, make());
    }
    const ptr = constants.get(key);
    runtime.exports.vir_obj_inc(ptr);
    return ptr;
  };
  const name = value => {
    if (typeof value !== "string") fail("expected name string");
    return cached(`name:${value}`, () => leaf("name", value));
  };
  const id = value => value === null ? runtime.makeObjectScalar(0, "none") : someCtor(() => idCtor(() => integer(value)));
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
  const json = value => {
    if (value === null) return jsonCtors.null();
    switch (typeof value) {
      case "boolean": return jsonCtors.bool(() => value ? 1 : 0);
      case "number": return jsonCtors.num(() => numberCtor(() => integer(value, true), () => integer(0)));
      case "string": return jsonCtors.str(() => string(value));
      case "object": {
        if (Array.isArray(value)) return jsonCtors.arr(() => sequence(value, json));
        const keys = Object.keys(value).sort(compareKeys);
        // This experimental adapter builds a size-balanced raw map from sorted
        // unique keys. Its layout is generated, but this container algorithm is
        // pinned implementation knowledge, not a public generic codec promise.
        const tree = (lo, hi) => {
          if (lo === hi) return mapLeaf();
          const middle = (lo + hi) >>> 1, key = keys[middle];
          return mapInner(() => integer(hi - lo), () => string(key), () => json(value[key]),
            () => tree(lo, middle), () => tree(middle + 1, hi));
        };
        return jsonCtors.obj(() => mapCtor(() => dependentMapCtor(() => tree(0, keys.length))));
      }
      default: fail("unchecked JSON value");
    }
  };
  const manualInline = value => manualInlineCtor(() => name(field(value, "name")), () => id(field(value, "id")),
    () => json(field(value, "data")));
  const manualBlock = value => manualBlockCtor(() => name(field(value, "name")), () => id(field(value, "id")),
    () => json(field(value, "data")), () => {
      const properties = field(value, "properties");
      return Object.keys(object(properties)).length === 0
        ? cached("empty-properties", () => leaf("properties", properties)) : leaf("properties", properties);
    });
  const inline = value => {
    const kind = single(value), v = value[kind];
    switch (kind) {
      case "text": case "code": case "linebreak": return inlineCtors[kind](() => string(v));
      case "emph": case "bold": case "concat": return inlineCtors[kind](() => sequence(v, inline));
      case "math": return inlineCtors.math(() => {
        const mode = field(v, "mode");
        if (mode !== "inline" && mode !== "display") fail("unsupported math mode");
        return definitions.get(`Lean.Doc.MathMode.${mode}`).tag;
      }, () => string(field(v, "str")));
      case "link": return inlineCtors.link(() => sequence(field(v, "content"), inline), () => string(field(v, "url")));
      case "footnote": return inlineCtors.footnote(() => string(field(v, "name")), () => sequence(field(v, "content"), inline));
      case "image": return inlineCtors.image(() => string(field(v, "alt")), () => string(field(v, "url")));
      case "other": return inlineCtors.other(() => manualInline(field(v, "container")), () => sequence(field(v, "content"), inline));
      default: fail(`unknown inline: ${kind}`);
    }
  };
  const block = value => {
    object(value);
    // Preserve Verso Block.fromJson?'s constructor precedence (not single-key).
    const kind = ["para", "code", "ul", "ol", "dl", "blockquote", "concat", "other"].find(key => Object.hasOwn(value, key));
    const v = value[kind];
    switch (kind) {
      case "para": return blockCtors.para(() => sequence(v, inline));
      case "code": return blockCtors.code(() => string(v));
      case "ul": return blockCtors.ul(() => sequence(v, item => listCtor(() => sequence(field(item, "contents"), block))));
      case "ol": return blockCtors.ol(() => integer(field(v, "start"), true),
        () => sequence(field(v, "items"), item => listCtor(() => sequence(field(item, "contents"), block))));
      case "dl": return blockCtors.dl(() => sequence(v, item => descCtor(
        () => sequence(field(item, "term"), inline), () => sequence(field(item, "contents"), block))));
      case "blockquote": case "concat": return blockCtors[kind](() => sequence(v, block));
      case "other": return blockCtors.other(() => manualBlock(field(v, "container")), () => sequence(field(v, "content"), block));
      default: fail("expected block constructor");
    }
  };
  const part = value => partCtor(() => sequence(field(value, "title"), inline), () => string(field(value, "titleString")),
    () => leaf("metadata", field(value, "metadata")), () => sequence(field(value, "content"), block),
    () => sequence(field(value, "subParts"), part));
  const document = value => documentCtor(() => integer(field(value, "version")),
    () => string(Object.hasOwn(value, "correlationId") ? value.correlationId : ""),
    () => string(Object.hasOwn(value, "cursorToken") ? value.cursorToken : ""),
    () => optionString(Object.hasOwn(value, "focus") ? value.focus : null),
    () => leaf("serverTiming", Object.hasOwn(value, "serverTiming") ? value.serverTiming : null),
    () => part(field(value, "document")));
  return input => {
    if (runtime.disposed || runtime.disposing) fail("runtime disposed");
    if (constants) fail("nested direct conversion");
    const checked = jsonBindings["jsonValue.check"](input);
    if (checked.kind !== "ok") fail(checked.value);
    const kind = single(input), v = input[kind];
    if (!Object.hasOwn(previewCtors, kind)) fail("unknown preview constructor");
    constants = new Map();
    let handle, ptr;
    try {
      ptr = previewCtors[kind](() => kind === "ready" ? document(field(v, "document")) : string(field(v, "message")));
      handle = runtime.makeLeanObjectHandleResource(ptr, "typed preview");
      return runtime.call(`${entry}.finish`, handle);
    } finally {
      if (handle) runtime.releaseLeanObjectHandleCell(runtime.leanObjectHandleCell(handle, "typed preview"));
      if (ptr !== undefined) runtime.exports.vir_obj_dec(ptr);
      for (const ptr of constants.values()) runtime.exports.vir_obj_dec(ptr);
      constants = undefined;
    }
  };
}
