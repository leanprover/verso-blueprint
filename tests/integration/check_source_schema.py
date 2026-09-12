"""Validate real Lean-serialized manifests, including inherited source fields."""

from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import subprocess
import tempfile

from jsonschema import Draft202012Validator, ValidationError


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "source-identity.json"
        subprocess.run(
            [
                "./scripts/lean-low-priority",
                "lake",
                "lean",
                "tests/SourceIdentityMain.lean",
                "--",
                "--run",
                "tests/SourceIdentityMain.lean",
                str(output),
            ],
            cwd=PACKAGE_ROOT,
            check=True,
        )
        fixture = json.loads(output.read_text(encoding="utf-8"))

    schema = fixture["schema"]
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    cases = fixture["cases"]
    assert {case["name"] for case in cases} == {
        "original", "anchor", "citation", "no-anchor", "no-citation", "location"
    }
    for case in cases:
        try:
            validator.validate(case["manifest"])
        except ValidationError as error:
            def details(error):
                if error.context:
                    return "\n".join(details(child) for child in error.context)
                path = ".".join(map(str, error.absolute_path))
                return f"{path}: {error.validator}: {error.message[:300]}"
            raise AssertionError(f"{case['name']}: {details(error)}") from None

    manifest = cases[0]["manifest"]
    primary_index = next(
        index for index, entry in enumerate(manifest["previews"])
        if entry["key"] == "source_identity_primary--statement"
    )

    rejection_count = 0

    def reject(name, invalid):
        nonlocal rejection_count
        try:
            validator.validate(invalid)
        except ValidationError:
            rejection_count += 1
            return
        raise AssertionError(f"Schema accepted {name}")

    def span(data):
        return data["previews"][primary_index]["sources"][0]["spans"][0]

    # Lean serializes optional fields as explicit nulls; absence is not the same
    # contract. Exercise every source-span field with the actual serialized data.
    for field in ("page", "anchor", "citation", "text", "pdf"):
        invalid = deepcopy(manifest)
        del span(invalid)[field]
        reject(f"missing span.{field}", invalid)
    for field in ("page", "anchor", "citation"):
        invalid = deepcopy(manifest)
        span(invalid)[field] = 12
        reject(f"numeric span.{field}", invalid)
    invalid = deepcopy(manifest)
    del invalid["sourceDocuments"][0]["title"]
    reject("missing inherited document title", invalid)
    invalid = deepcopy(manifest)
    invalid["sourceDocuments"][0] = {"toDocumentMetadata": invalid["sourceDocuments"][0]}
    reject("nested inherited document fields", invalid)
    # Graph visuals use Lean's omitted-field convention, not explicit nulls.
    for field, value in (("tooltip?", "obsolete key"), ("tooltip", None), ("gradientangle", 90)):
        invalid = deepcopy(manifest)
        invalid["graphs"][0]["nodes"][0]["visual"][field] = value
        reject(f"invalid graph visual {field}={value!r}", invalid)
    invalid = deepcopy(manifest)
    invalid["previews"][primary_index]["codeData"]["externalDecls"][0]["provedStatus"] = "unknown"
    reject("unknown formalization status", invalid)
    invalid = deepcopy(manifest)
    invalid["previews"][primary_index]["codeData"]["externalDecls"][0]["range"]["pos"] = [1]
    reject("incomplete Lean position tuple", invalid)
    print(f"Source schema: {len(cases)} serialized manifests and {rejection_count} rejection cases passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
