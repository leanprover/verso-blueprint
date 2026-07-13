from __future__ import annotations

import json
from pathlib import Path
import re


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
BLUEPRINT_SRC = PACKAGE_ROOT / "src" / "VersoBlueprint"
PUBLIC_API_CONTRACT = json.loads(
    (PACKAGE_ROOT / "tests" / "preview_runtime_api_contract.json").read_text(
        encoding="utf-8"
    )
)


def normalize_public_api_entry(entry: dict[str, str]) -> dict[str, str]:
    normalized = dict(entry)
    normalized["package_export"] = normalized.pop("packageExport")
    normalized["jsdoc_page"] = normalized.pop("jsdocPage")
    return normalized


PUBLIC_API_MODULES = {
    name: normalize_public_api_entry(entry)
    for name, entry in PUBLIC_API_CONTRACT["modules"].items()
}
PUBLIC_API_TYPES_MODULE = normalize_public_api_entry(
    PUBLIC_API_CONTRACT["typesModule"]
)
PUBLIC_API_PACKAGE_EXPORTS = {
    entry["package_export"]: {
        "source": entry["source"],
        "declaration": entry["declaration"],
    }
    for entry in [*PUBLIC_API_MODULES.values(), PUBLIC_API_TYPES_MODULE]
}
PUBLIC_API_JSDOC_SOURCES = {
    entry["source"]
    for entry in [*PUBLIC_API_MODULES.values(), PUBLIC_API_TYPES_MODULE]
}
PUBLIC_GENERATED_API_MODULES = {
    entry["generated"]
    for entry in PUBLIC_API_MODULES.values()
}
PUBLIC_DATA_API_EXPORTS = set(PUBLIC_API_CONTRACT["exports"]["data"])
PUBLIC_PREVIEW_API_EXPORTS = set(PUBLIC_API_CONTRACT["exports"]["preview"])
PUBLIC_GRAPH_API_EXPORTS = set(PUBLIC_API_CONTRACT["exports"]["graph"])
PUBLIC_API_TYPE_EXPORTS = set(PUBLIC_API_CONTRACT["typeExports"])
RUNTIME_BOOTSTRAP_JS = {
    Path("Commands/preview-runtime-base.mjs"),
    Path("Commands/preview-runtime-data.mjs"),
    Path("Commands/preview-runtime-render.mjs"),
    Path("Commands/preview-runtime-source-metadata.mjs"),
    Path("Commands/preview-runtime-hydration.mjs"),
    Path("Commands/preview-runtime-lifecycle.mjs"),
    Path("Commands/preview-runtime-surface.mjs"),
    Path("Commands/preview-runtime-template.mjs"),
    Path("Commands/preview-runtime-api.mjs"),
    Path("blueprint-api-common.mjs"),
    Path("Commands/graph.mjs"),
    Path("blueprint-graph-api.mjs"),
    Path("blueprint-graph-core.mjs"),
    Path("blueprint-data-api.mjs"),
    Path("blueprint-page-runtime.mjs"),
    Path("blueprint-preview-api.mjs"),
    Path("blueprint-preview-core.mjs"),
}


def blueprint_js_files() -> list[Path]:
    return sorted([*BLUEPRINT_SRC.rglob("*.js"), *BLUEPRINT_SRC.rglob("*.mjs")])


def blueprint_js_source() -> str:
    return "\n\n".join(
        path.read_text(encoding="utf-8")
        for path in blueprint_js_files()
    )


def find_balanced_js_object_body(source: str, name: str) -> str:
    match = re.search(rf"\bconst\s+{re.escape(name)}\s*=\s*{{", source)
    if match is None:
        raise AssertionError(f"missing JavaScript object literal {name}")
    depth = 1
    pos = match.end()
    while pos < len(source):
        char = source[pos]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[match.end():pos]
        pos += 1
    raise AssertionError(f"unterminated JavaScript object literal {name}")


def js_object_methods(source: str, name: str) -> set[str]:
    body = find_balanced_js_object_body(source, name)
    return set(re.findall(r"^\s+([A-Za-z][A-Za-z0-9_]*):", body, flags=re.MULTILINE))


def js_object_keys(source: str, name: str) -> set[str]:
    body = find_balanced_js_object_body(source, name)
    return set(
        re.findall(
            r"^\s+([A-Za-z][A-Za-z0-9_]*)(?=\s*(?::|,|$))",
            body,
            flags=re.MULTILINE,
        )
    )


def esm_named_exports(source: str) -> set[str]:
    exports = set(
        re.findall(
            r"^export\s+(?:async\s+)?(?:function|const|let|var|class)\s+([A-Za-z][A-Za-z0-9_]*)",
            source,
            flags=re.MULTILINE,
        )
    )
    for body in re.findall(r"^export\s*{\s*([^}]+)\s*};", source, flags=re.MULTILINE):
        for raw_name in body.split(","):
            name = raw_name.strip()
            if not name:
                continue
            if " as " in name:
                name = name.rsplit(" as ", 1)[1].strip()
            if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name):
                exports.add(name)
    return exports


def runtime_api_methods(name: str) -> list[str]:
    return sorted(js_object_methods(blueprint_js_source(), name))


def markdown_table(source: str, header: str) -> str:
    start = source.index(header)
    end = source.find("\n\n", start)
    return source[start:] if end < 0 else source[start:end]


def documented_public_api_methods(source: str) -> set[str]:
    table = markdown_table(source, "| Entry point | Use |")
    return set(re.findall(r"`api\.([A-Za-z][A-Za-z0-9_]*)\(", table))


def documented_bundled_helper_methods(source: str) -> set[str]:
    table = markdown_table(source, "| Helper family | Helpers | Bundled consumers |")
    return set(re.findall(r"`([A-Za-z][A-Za-z0-9_]*)`", table))
